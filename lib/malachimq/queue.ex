defmodule MalachiMQ.Queue do
  @moduledoc """
  Individual queue using ETS for maximum performance.
  Optimized for machines with many cores.
  """
  use GenServer
  require Logger

  @ets_opts [
    :ordered_set,
    :public,
    :named_table,
    read_concurrency: true,
    write_concurrency: true,
    decentralized_counters: true
  ]

  def start_link({name, partition}) do
    GenServer.start_link(__MODULE__, {name, partition}, name: via_tuple({name, partition}))
  end

  def enqueue(queue_name, payload, headers \\ %{}) do
    {name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)

    ensure_started({name, partition})

    # Register producer for stats tracking
    GenServer.cast(via_tuple({name, partition}), {:register_producer, self()})

    MalachiMQ.Metrics.increment_enqueued(queue_name)

    message_id = :erlang.unique_integer([:monotonic, :positive])

    message = %{
      id: message_id,
      payload: payload,
      headers: headers,
      timestamp: System.system_time(:microsecond),
      queue: queue_name
    }

    consumers_table = consumers_name({name, partition})

    case dispatch_from_ets(consumers_table, message) do
      :dispatched ->
        :ok

      :no_consumers ->
        buffer_table = buffer_name({name, partition})
        :ets.insert(buffer_table, {message_id, message})
        :ok
    end
  end

  def subscribe(queue_name, consumer_pid) do
    {name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)
    ensure_started({name, partition})

    consumers_table = consumers_name({name, partition})
    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, 0)

    :ets.insert(consumers_table, {consumer_pid, counter, System.monotonic_time()})

    GenServer.cast(via_tuple({name, partition}), {:new_consumer, consumer_pid})
  end

  def get_stats(queue_name) do
    {name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)

    case GenServer.whereis(via_tuple({name, partition})) do
      nil ->
        %{exists: false, consumers: 0, producers: 0, buffered: 0, partition: partition}

      pid ->
        GenServer.call(pid, :get_stats, 1000)
    end
  end

  @doc """
  Removes all consumers from a queue.
  Returns {:ok, removed_count}
  """
  def kill_all_consumers(queue_name) do
    {name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)

    case GenServer.whereis(via_tuple({name, partition})) do
      nil ->
        {:ok, 0}

      pid ->
        GenServer.call(pid, :kill_all_consumers)
    end
  end

  @doc """
  Lists all consumer PIDs from a queue.
  """
  def list_consumers(queue_name) do
    {name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)

    case GenServer.whereis(via_tuple({name, partition})) do
      nil ->
        []

      pid ->
        GenServer.call(pid, :list_consumers)
    end
  end

  @doc """
  Removes a specific consumer by PID.
  """
  def kill_consumer(queue_name, consumer_pid) do
    {name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)

    case GenServer.whereis(via_tuple({name, partition})) do
      nil ->
        {:error, :queue_not_found}

      pid ->
        GenServer.call(pid, {:kill_consumer, consumer_pid})
    end
  end

  @impl true
  def init({name, partition}) do
    consumers_table = :ets.new(consumers_name({name, partition}), @ets_opts)

    buffer_table =
      :ets.new(
        buffer_name({name, partition}),
        [:ordered_set, :public, :named_table, write_concurrency: true]
      )

    producers_table =
      :ets.new(
        producers_name({name, partition}),
        [:set, :public, :named_table, read_concurrency: true, write_concurrency: true]
      )

    message_counter = :atomics.new(1, signed: false)
    :atomics.put(message_counter, 1, 0)

    state = %{
      name: name,
      partition: partition,
      consumers_table: consumers_table,
      buffer_table: buffer_table,
      producers_table: producers_table,
      message_counter: message_counter
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:new_consumer, consumer_pid}, state) do
    Process.monitor(consumer_pid)

    flush_buffer(consumer_pid, state.buffer_table)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:register_producer, producer_pid}, state) do
    # Only insert if not already registered
    case :ets.lookup(state.producers_table, producer_pid) do
      [] ->
        :ets.insert(state.producers_table, {producer_pid, System.monotonic_time()})
        Process.monitor(producer_pid)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    consumers = :ets.info(state.consumers_table, :size)
    producers = :ets.info(state.producers_table, :size)
    buffered = :ets.info(state.buffer_table, :size)
    total_messages = :atomics.get(state.message_counter, 1)

    stats = %{
      exists: true,
      name: state.name,
      partition: state.partition,
      consumers: consumers,
      producers: producers,
      buffered: buffered,
      total_messages: total_messages,
      memory_kb:
        div(
          (:ets.info(state.consumers_table, :memory) + :ets.info(state.buffer_table, :memory)) * 8,
          1024
        )
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:kill_all_consumers, _from, state) do
    consumers = :ets.tab2list(state.consumers_table)
    count = length(consumers)

    Enum.each(consumers, fn {consumer_pid, _counter, _ts} ->
      Process.exit(consumer_pid, :kill)
      :ets.delete(state.consumers_table, consumer_pid)
    end)

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call(:list_consumers, _from, state) do
    consumers =
      :ets.tab2list(state.consumers_table)
      |> Enum.map(fn {pid, _counter, ts} ->
        %{
          pid: pid,
          alive: Process.alive?(pid),
          registered_at: ts
        }
      end)

    {:reply, consumers, state}
  end

  @impl true
  def handle_call({:kill_consumer, consumer_pid}, _from, state) do
    case :ets.lookup(state.consumers_table, consumer_pid) do
      [{^consumer_pid, _counter, _ts}] ->
        Process.exit(consumer_pid, :kill)
        :ets.delete(state.consumers_table, consumer_pid)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove from consumers table
    :ets.delete(state.consumers_table, pid)
    # Remove from producers table
    :ets.delete(state.producers_table, pid)
    {:noreply, state}
  end

  defp via_tuple({name, partition}) do
    {:via, Registry, {MalachiMQ.QueueRegistry, {name, partition}}}
  end

  defp consumers_name({name, partition}), do: :"malachimq_consumers_#{name}_#{partition}"
  defp buffer_name({name, partition}), do: :"malachimq_buffer_#{name}_#{partition}"
  defp producers_name({name, partition}), do: :"malachimq_producers_#{name}_#{partition}"

  defp ensure_started({name, partition}) do
    case GenServer.whereis(via_tuple({name, partition})) do
      nil ->
        spec = {__MODULE__, {name, partition}}

        case DynamicSupervisor.start_child(MalachiMQ.QueueSupervisor, spec) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> error
        end

      _pid ->
        :ok
    end
  end

  defp dispatch_from_ets(consumers_table, message) do
    case :ets.first(consumers_table) do
      :"$end_of_table" ->
        :no_consumers

      consumer_pid ->
        if Process.whereis(MalachiMQ.AckManager) do
          MalachiMQ.AckManager.track_message(
            message.id,
            message.queue,
            consumer_pid,
            message
          )
        end

        send(consumer_pid, {:queue_message, message})

        case :ets.lookup(consumers_table, consumer_pid) do
          [{^consumer_pid, counter, _ts}] ->
            :atomics.add(counter, 1, 1)
            :ets.delete(consumers_table, consumer_pid)
            :ets.insert(consumers_table, {consumer_pid, counter, System.monotonic_time()})

          _ ->
            :ok
        end

        :dispatched
    end
  end

  defp flush_buffer(consumer_pid, buffer_table) do
    case :ets.first(buffer_table) do
      :"$end_of_table" ->
        :ok

      key ->
        case :ets.lookup(buffer_table, key) do
          [{^key, message}] ->
            # Track message in AckManager before sending
            if Process.whereis(MalachiMQ.AckManager) do
              MalachiMQ.AckManager.track_message(
                message.id,
                message.queue,
                consumer_pid,
                message
              )
            end

            send(consumer_pid, {:queue_message, message})
            :ets.delete(buffer_table, key)
            flush_buffer(consumer_pid, buffer_table)

          [] ->
            flush_buffer(consumer_pid, buffer_table)
        end
    end
  end
end
