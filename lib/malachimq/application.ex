defmodule MalachiMQ.Application do
  use Application

  def start(_type, _args) do
    port = Application.get_env(:malachimq, :tcp_port, 4040)
    dashboard_port = Application.get_env(:malachimq, :dashboard_port, 4041)

    available_schedulers = System.schedulers_online()
    configured_schedulers = Application.get_env(:malachimq, :schedulers, available_schedulers)
    schedulers_to_use = min(configured_schedulers, available_schedulers)

    :erlang.system_flag(:schedulers_online, schedulers_to_use)

    children = [
      {Registry,
       keys: :unique, name: MalachiMQ.QueueRegistry, partitions: System.schedulers_online()},

      {DynamicSupervisor,
       name: MalachiMQ.QueueSupervisor, strategy: :one_for_one, max_children: 100_000},

      {Task.Supervisor, name: MalachiMQ.TaskSupervisor, max_children: 10_000},

      MalachiMQ.PartitionManager,

      MalachiMQ.Metrics,

      MalachiMQ.Auth,

      MalachiMQ.AckManager,

      {MalachiMQ.TCPAcceptorPool, port},

      {MalachiMQ.Dashboard, dashboard_port}
    ]

    opts = [strategy: :one_for_one, name: MalachiMQ.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule MalachiMQ.PartitionManager do
  @moduledoc """
  Manages partitions to distribute load across available cores.
  Number of partitions calculated dynamically based on hardware.
  """
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def get_partition(queue_name) do
    partition = :erlang.phash2(queue_name, get_partition_count())
    {queue_name, partition}
  end

  def get_partition_count do
    multiplier = Application.get_env(:malachimq, :partition_multiplier, 100)
    System.schedulers_online() * multiplier
  end

  @impl true
  def init(:ok) do
    partitions = get_partition_count()
    schedulers = System.schedulers_online()
    multiplier = div(partitions, schedulers)

    Logger.info(
      I18n.t(:partition_manager_started,
        partitions: partitions,
        schedulers: schedulers,
        multiplier: multiplier
      )
    )

    {:ok, %{}}
  end
end

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

    MalachiMQ.Metrics.increment_enqueued(queue_name)

    message_id = :erlang.unique_integer([:monotonic, :positive])

    message = %{
      id: message_id,
      payload: payload,
      headers: headers,
      timestamp: System.system_time(:microsecond),
      queue: queue_name
    }

    ets_table = ets_name({name, partition})

    case dispatch_from_ets(ets_table, message) do
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

    ets_table = ets_name({name, partition})
    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, 0)

    :ets.insert(ets_table, {consumer_pid, counter, System.monotonic_time()})

    GenServer.cast(via_tuple({name, partition}), {:new_consumer, consumer_pid})
  end

  def get_stats(queue_name) do
    {name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)

    case GenServer.whereis(via_tuple({name, partition})) do
      nil ->
        %{exists: false, consumers: 0, buffered: 0, partition: partition}

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
    ets_table = :ets.new(ets_name({name, partition}), @ets_opts)

    buffer_table =
      :ets.new(
        buffer_name({name, partition}),
        [:ordered_set, :public, :named_table, write_concurrency: true]
      )

    message_counter = :atomics.new(1, signed: false)
    :atomics.put(message_counter, 1, 0)

    state = %{
      name: name,
      partition: partition,
      ets_table: ets_table,
      buffer_table: buffer_table,
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
  def handle_call(:get_stats, _from, state) do
    consumers = :ets.info(state.ets_table, :size)
    buffered = :ets.info(state.buffer_table, :size)
    total_messages = :atomics.get(state.message_counter, 1)

    stats = %{
      exists: true,
      name: state.name,
      partition: state.partition,
      consumers: consumers,
      buffered: buffered,
      total_messages: total_messages,
      memory_kb:
        div(
          (:ets.info(state.ets_table, :memory) + :ets.info(state.buffer_table, :memory)) * 8,
          1024
        )
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:kill_all_consumers, _from, state) do
    consumers = :ets.tab2list(state.ets_table)
    count = length(consumers)

    Enum.each(consumers, fn {consumer_pid, _counter, _ts} ->
      Process.exit(consumer_pid, :kill)
      :ets.delete(state.ets_table, consumer_pid)
    end)

    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call(:list_consumers, _from, state) do
    consumers =
      :ets.tab2list(state.ets_table)
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
    case :ets.lookup(state.ets_table, consumer_pid) do
      [{^consumer_pid, _counter, _ts}] ->
        Process.exit(consumer_pid, :kill)
        :ets.delete(state.ets_table, consumer_pid)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    :ets.delete(state.ets_table, pid)
    {:noreply, state}
  end

  defp via_tuple({name, partition}) do
    {:via, Registry, {MalachiMQ.QueueRegistry, {name, partition}}}
  end

  defp ets_name({name, partition}), do: :"malachimq_consumers_#{name}_#{partition}"
  defp buffer_name({name, partition}), do: :"malachimq_buffer_#{name}_#{partition}"

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

  defp dispatch_from_ets(ets_table, message) do
    case :ets.first(ets_table) do
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

        case :ets.lookup(ets_table, consumer_pid) do
          [{^consumer_pid, counter, _ts}] ->
            :atomics.add(counter, 1, 1)
            :ets.delete(ets_table, consumer_pid)
            :ets.insert(ets_table, {consumer_pid, counter, System.monotonic_time()})

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
            send(consumer_pid, {:queue_message, message})
            :ets.delete(buffer_table, key)
            flush_buffer(consumer_pid, buffer_table)

          [] ->
            flush_buffer(consumer_pid, buffer_table)
        end
    end
  end
end

defmodule MalachiMQ.Consumer do
  @moduledoc """
  Ultra-lightweight consumer with aggressive hibernation.
  """
  use GenServer, restart: :temporary
  require Logger
  alias MalachiMQ.I18n

  def start_link({queue_name, callback, opts}) do
    GenServer.start_link(__MODULE__, {queue_name, callback, opts})
  end

  @impl true
  def init({queue_name, callback, _opts}) do
    Process.flag(:message_queue_data, :off_heap)

    MalachiMQ.Queue.subscribe(queue_name, self())

    state = %{
      queue_name: queue_name,
      callback: callback,
      processed: 0,
      last_gc: System.monotonic_time(:millisecond)
    }

    {:ok, state, {:continue, :maybe_hibernate}}
  end

  @impl true
  def handle_continue(:maybe_hibernate, state) do
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_info({:queue_message, message}, state) do
    _start_time = System.monotonic_time(:microsecond)

    try do
      result = state.callback.(message)

      latency = System.monotonic_time(:microsecond) - message.timestamp
      MalachiMQ.Metrics.record_latency(state.queue_name, latency)
      MalachiMQ.Metrics.increment_processed(state.queue_name)

      if Process.whereis(MalachiMQ.AckManager) do
        case result do
          :error ->
            MalachiMQ.AckManager.nack(message.id, requeue: true)

          {:error, _reason} ->
            MalachiMQ.AckManager.nack(message.id, requeue: true)

          _ ->
            MalachiMQ.AckManager.ack(message.id)
        end
      end
    rescue
      e ->
        Logger.error(I18n.t(:processing_error, error: inspect(e)))
        MalachiMQ.Metrics.increment_errors(state.queue_name)

        if Process.whereis(MalachiMQ.AckManager) do
          MalachiMQ.AckManager.nack(message.id, requeue: true)
        end
    end

    new_processed = state.processed + 1
    now = System.monotonic_time(:millisecond)

    gc_interval = Application.get_env(:malachimq, :gc_interval_ms, 10_000)

    new_state =
      if now - state.last_gc > gc_interval do
        :erlang.garbage_collect(self())
        %{state | processed: new_processed, last_gc: now}
      else
        %{state | processed: new_processed}
      end

    hibernate_every = Application.get_env(:malachimq, :hibernate_every, 1000)

    if rem(new_processed, hibernate_every) == 0 do
      {:noreply, new_state, :hibernate}
    else
      {:noreply, new_state}
    end
  end
end

defmodule MalachiMQ.TCPAcceptorPool do
  @moduledoc """
  TCP acceptor pool - quantity based on available cores.
  """
  use Supervisor
  require Logger
  alias MalachiMQ.I18n

  def start_link(port) do
    Supervisor.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port) do
    buffer_size = Application.get_env(:malachimq, :tcp_buffer_size, 32768)
    backlog = Application.get_env(:malachimq, :tcp_backlog, 4096)
    send_timeout = Application.get_env(:malachimq, :tcp_send_timeout, 3000)

    opts = [
      :binary,
      packet: :line,
      active: false,
      reuseaddr: true,
      reuseport: true,
      nodelay: true,
      keepalive: true,
      send_timeout: send_timeout,
      send_timeout_close: true,
      sndbuf: buffer_size,
      recbuf: buffer_size,
      backlog: backlog
    ]

    case :gen_tcp.listen(port, opts) do
      {:ok, _socket} ->
        num_acceptors = System.schedulers_online()
        Logger.info(I18n.t(:tcp_server_started, port: port, acceptors: num_acceptors))

        children =
          for i <- 1..num_acceptors do
            Supervisor.child_spec(
              {MalachiMQ.TCPAcceptor, {port, opts, i}},
              id: :"acceptor_#{i}"
            )
          end

        Supervisor.init(children, strategy: :one_for_one)

      {:error, reason} ->
        {:stop, reason}
    end
  end
end

defmodule MalachiMQ.TCPAcceptor do
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  def start_link({port, opts, id}) do
    GenServer.start_link(__MODULE__, {port, opts, id})
  end

  @impl true
  def init({port, opts, id}) do
    {:ok, socket} = :gen_tcp.listen(port, opts)
    Logger.info(I18n.t(:acceptor_started, id: id))
    send(self(), :accept)
    {:ok, %{socket: socket, id: id, connections: 0, idle_count: 0}}
  end

  @impl true
  def handle_info(:accept, %{socket: socket, idle_count: idle_count} = state) do
    timeout = min(100 + (idle_count * 50), 30000)

    case :gen_tcp.accept(socket, timeout) do
      {:ok, client} ->
        spawn_link(fn -> handle_client(client) end)
        send(self(), :accept)
        {:noreply, %{state | connections: state.connections + 1, idle_count: 0}}

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, %{state | idle_count: min(idle_count + 1, 20)}}

      {:error, reason} ->
        Logger.error(I18n.t(:accept_error, reason: inspect(reason)))
        Process.sleep(10)
        send(self(), :accept)
        {:noreply, state}
    end
  end

  defp handle_client(socket) do
    case authenticate_client(socket) do
      {:ok, session} ->
        receive_loop(socket, session)

      {:error, reason} ->
        send_error(socket, reason)
        :gen_tcp.close(socket)
    end
  end

  defp authenticate_client(socket) do
    :inet.setopts(socket, active: false)
    recv_timeout = Application.get_env(:malachimq, :auth_timeout_ms, 10_000)

    case :gen_tcp.recv(socket, 0, recv_timeout) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"action" => "auth", "username" => username, "password" => password}} ->
            case MalachiMQ.Auth.authenticate(username, password) do
              {:ok, token} ->
                case MalachiMQ.Auth.validate_token(token) do
                  {:ok, session} ->
                    response = Jason.encode!(%{"s" => "ok", "token" => token})
                    :gen_tcp.send(socket, response <> "\n")
                    {:ok, session}

                  {:error, _} ->
                    {:error, :invalid_token}
                end

              {:error, _reason} ->
                {:error, :invalid_credentials}
            end

          _ ->
            {:error, :auth_required}
        end

      {:error, _} ->
        {:error, :connection_error}
    end
  end

  defp receive_loop(socket, session) do
    recv_timeout = Application.get_env(:malachimq, :tcp_recv_timeout, 30_000)

    case :gen_tcp.recv(socket, 0, recv_timeout) do
      {:ok, data} ->
        process_authenticated(socket, data, session)
        receive_loop(socket, session)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  @compile {:inline, process_authenticated: 3}
  defp process_authenticated(socket, data, session) do
    case Jason.decode(data) do
      {:ok, %{"action" => "publish", "queue_name" => q, "payload" => p} = msg} ->
        if MalachiMQ.Auth.has_permission?(session.permissions, :produce) do
          h = Map.get(msg, "headers", %{})
          MalachiMQ.Queue.enqueue(q, p, h)
          :gen_tcp.send(socket, ~s({"s":"ok"}\n))
        else
          Logger.warning(I18n.t(:permission_denied, username: session.username, action: "publish"))
          :gen_tcp.send(socket, ~s({"s":"err","reason":"permission_denied"}\n))
        end

      {:ok, %{"action" => "subscribe", "queue_name" => q}} ->
        if MalachiMQ.Auth.has_permission?(session.permissions, :consume) do
          MalachiMQ.Queue.subscribe(q, self())
          :gen_tcp.send(socket, ~s({"s":"ok"}\n))
        else
          Logger.warning(I18n.t(:permission_denied, username: session.username, action: "subscribe"))
          :gen_tcp.send(socket, ~s({"s":"err","reason":"permission_denied"}\n))
        end

      {:ok, %{"queue_name" => q, "payload" => p} = msg} ->
        if MalachiMQ.Auth.has_permission?(session.permissions, :produce) do
          h = Map.get(msg, "headers", %{})
          MalachiMQ.Queue.enqueue(q, p, h)
          :gen_tcp.send(socket, ~s({"s":"ok"}\n))
        else
          :gen_tcp.send(socket, ~s({"s":"err","reason":"permission_denied"}\n))
        end

      _ ->
        :gen_tcp.send(socket, ~s({"s":"err","reason":"invalid_request"}\n))
    end
  end

  defp send_error(socket, :invalid_credentials) do
    :gen_tcp.send(socket, ~s({"s":"err","reason":"invalid_credentials"}\n))
  end

  defp send_error(socket, :auth_required) do
    :gen_tcp.send(socket, ~s({"s":"err","reason":"auth_required"}\n))
  end

  defp send_error(socket, _) do
    :gen_tcp.send(socket, ~s({"s":"err","reason":"error"}\n))
  end
end

defmodule MalachiMQ.Benchmark do
  @moduledoc """
  System benchmarking tools.
  """
  require Logger
  alias MalachiMQ.I18n

  def spawn_consumers(queue_name, count, callback \\ nil) do
    callback =
      callback ||
        fn msg ->
          log_every = Application.get_env(:malachimq, :benchmark_log_every, 100_000)

          if rem(msg.id, log_every) == 0 do
            Logger.info(I18n.t(:processed_message, id: msg.id))
          end
        end

    Logger.info(I18n.t(:creating_consumers, count: count))

    start_time = System.monotonic_time(:millisecond)
    max_concurrency = Application.get_env(:malachimq, :spawn_concurrency, 1000)

    _tasks =
      1..count
      |> Task.async_stream(
        fn i ->
          opts = [hibernate: true]
          {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, opts})
          log_every = Application.get_env(:malachimq, :benchmark_log_every, 10_000)
          if rem(i, log_every) == 0, do: Logger.info(I18n.t(:consumers_created_progress, count: i))
        end,
        max_concurrency: max_concurrency,
        timeout: :infinity
      )
      |> Stream.run()

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info(I18n.t(:consumers_created, count: count, duration: duration))
    Logger.info(I18n.t(:consumers_rate, rate: round(count / (duration / 1000))))

    :erlang.garbage_collect()
    memory_mb = :erlang.memory(:total) / 1_048_576
    Logger.info(I18n.t(:total_memory, memory: Float.round(memory_mb, 2)))
    Logger.info(I18n.t(:memory_per_consumer, memory: round(memory_mb * 1024 / count)))
  end

  def send_messages(queue_name, count) do
    Logger.info(I18n.t(:sending_messages, count: count))

    start_time = System.monotonic_time(:millisecond)
    max_concurrency = Application.get_env(:malachimq, :send_concurrency, 1000)

    1..count
    |> Task.async_stream(
      fn i ->
        MalachiMQ.Queue.enqueue(
          queue_name,
          "Message ##{i}",
          %{"index" => i}
        )
      end,
      max_concurrency: max_concurrency
    )
    |> Stream.run()

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info(I18n.t(:messages_sent, count: count, duration: duration))
    Logger.info(I18n.t(:messages_rate, rate: round(count / (duration / 1000))))
  end

  def system_info do
    %{
      schedulers: :erlang.system_info(:schedulers_online),
      processes: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      memory_mb: :erlang.memory(:total) / 1_048_576,
      ets_tables: length(:ets.all()),
      ets_limit: :erlang.system_info(:ets_limit)
    }
    |> IO.inspect(label: "MalachiMQ System Info")
  end
end

defmodule MalachiMQ.Metrics do
  @moduledoc """
  Real-time metrics system using ETS and atomic counters.
  """
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  @metrics_table :malachimq_metrics

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def increment_enqueued(queue_name) do
    key = {:enqueued, queue_name}
    :ets.update_counter(@metrics_table, key, {2, 1}, {key, 0})
    :ok
  end

  def increment_processed(queue_name) do
    key = {:processed, queue_name}
    :ets.update_counter(@metrics_table, key, {2, 1}, {key, 0})
    :ok
  end

  def increment_errors(queue_name) do
    key = {:errors, queue_name}
    :ets.update_counter(@metrics_table, key, {2, 1}, {key, 0})
    :ok
  end

  def increment_acked(queue_name) do
    key = {:acked, queue_name}
    :ets.update_counter(@metrics_table, key, {2, 1}, {key, 0})
    :ok
  end

  def increment_nacked(queue_name) do
    key = {:nacked, queue_name}
    :ets.update_counter(@metrics_table, key, {2, 1}, {key, 0})
    :ok
  end

  def increment_retried(queue_name) do
    key = {:retried, queue_name}
    :ets.update_counter(@metrics_table, key, {2, 1}, {key, 0})
    :ok
  end

  def increment_dead_lettered(queue_name) do
    key = {:dead_lettered, queue_name}
    :ets.update_counter(@metrics_table, key, {2, 1}, {key, 0})
    :ok
  end

  def record_latency(queue_name, latency_us) do
    key = {:latency, queue_name}

    case :ets.lookup(@metrics_table, key) do
      [] ->
        :ets.insert(@metrics_table, {key, {latency_us, 1, latency_us, latency_us}})

      [{^key, {sum, count, min, max}}] ->
        new_sum = sum + latency_us
        new_count = count + 1
        new_min = min(min, latency_us)
        new_max = max(max, latency_us)
        :ets.insert(@metrics_table, {key, {new_sum, new_count, new_min, new_max}})
    end

    :ok
  end

  def get_metrics(queue_name) do
    enqueued = get_counter({:enqueued, queue_name})
    processed = get_counter({:processed, queue_name})
    errors = get_counter({:errors, queue_name})
    acked = get_counter({:acked, queue_name})
    nacked = get_counter({:nacked, queue_name})
    retried = get_counter({:retried, queue_name})
    dead_lettered = get_counter({:dead_lettered, queue_name})
    latency = get_latency_stats({:latency, queue_name})

    pending_ack =
      if Code.ensure_loaded?(MalachiMQ.AckManager) and Process.whereis(MalachiMQ.AckManager) do
        MalachiMQ.AckManager.pending_count(queue_name)
      else
        0
      end

    %{
      queue: queue_name,
      enqueued: enqueued,
      processed: processed,
      errors: errors,
      acked: acked,
      nacked: nacked,
      retried: retried,
      dead_lettered: dead_lettered,
      pending_ack: pending_ack,
      latency_us: latency,
      queue_stats: MalachiMQ.Queue.get_stats(queue_name)
    }
  end

  def get_all_metrics do
    queues = get_all_queues()

    Enum.map(queues, fn queue_name ->
      get_metrics(queue_name)
    end)
  end

  def get_system_metrics do
    memory = :erlang.memory()
    {{:input, input_bytes}, {:output, output_bytes}} = :erlang.statistics(:io)

    %{
      timestamp: System.system_time(:second),
      schedulers_online: :erlang.system_info(:schedulers_online),
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      run_queue: :erlang.statistics(:run_queue),
      memory: %{
        total_mb: memory[:total] / 1_048_576,
        processes_mb: memory[:processes] / 1_048_576,
        ets_mb: memory[:ets] / 1_048_576,
        atom_mb: memory[:atom] / 1_048_576,
        binary_mb: memory[:binary] / 1_048_576
      },
      ets_tables: length(:ets.all()),
      io: %{
        input_bytes: input_bytes,
        output_bytes: output_bytes
      },
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
    }
  end

  def reset_metrics(queue_name) do
    GenServer.call(__MODULE__, {:reset, queue_name})
  end

  @impl true
  def init(:ok) do
    :ets.new(@metrics_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(:malachimq_metrics_history, [
      :ordered_set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    schedule_snapshot()
    schedule_cleanup()

    Logger.info(I18n.t(:metrics_started))
    {:ok, %{}}
  end

  @impl true
  def handle_call({:reset, queue_name}, _from, state) do
    :ets.delete(@metrics_table, {:enqueued, queue_name})
    :ets.delete(@metrics_table, {:processed, queue_name})
    :ets.delete(@metrics_table, {:errors, queue_name})
    :ets.delete(@metrics_table, {:latency, queue_name})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:snapshot, state) do
    take_snapshot()
    schedule_snapshot()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_snapshots()
    schedule_cleanup()
    {:noreply, state}
  end

  defp get_counter(key) do
    case :ets.lookup(@metrics_table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end

  defp get_latency_stats(key) do
    case :ets.lookup(@metrics_table, key) do
      [{^key, {sum, count, min, max}}] ->
        %{
          avg: div(sum, count),
          min: min,
          max: max,
          count: count
        }

      [] ->
        %{avg: 0, min: 0, max: 0, count: 0}
    end
  end

  defp get_all_queues do
    :ets.match(@metrics_table, {{:enqueued, :"$1"}, :_})
    |> Enum.map(fn [queue] -> queue end)
    |> Enum.uniq()
  end

  defp schedule_snapshot do
    interval = Application.get_env(:malachimq, :metrics_snapshot_interval_ms, 1_000)
    Process.send_after(self(), :snapshot, interval)
  end

  defp schedule_cleanup do
    interval = Application.get_env(:malachimq, :metrics_cleanup_interval_ms, 60_000)
    Process.send_after(self(), :cleanup, interval)
  end

  defp take_snapshot do
    timestamp = System.system_time(:second)
    metrics = get_all_metrics()
    system = get_system_metrics()

    snapshot = %{
      timestamp: timestamp,
      queues: metrics,
      system: system
    }

    :ets.insert(:malachimq_metrics_history, {timestamp, snapshot})
  end

  defp cleanup_old_snapshots do
    history_seconds = Application.get_env(:malachimq, :metrics_history_seconds, 300)
    cutoff = System.system_time(:second) - history_seconds

    :ets.select_delete(:malachimq_metrics_history, [
      {{:"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  def get_history(seconds \\ 60) do
    cutoff = System.system_time(:second) - seconds

    :ets.select(:malachimq_metrics_history, [
      {{:"$1", :"$2"}, [{:>=, :"$1", cutoff}], [:"$2"]}
    ])
  end
end

defmodule MalachiMQ.Dashboard do
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port) do
    opts = [:binary, packet: :http, active: false, reuseaddr: true]

    case :gen_tcp.listen(port, opts) do
      {:ok, socket} ->
        Logger.info(I18n.t(:dashboard_started, port: port))
        send(self(), :accept)
        {:ok, %{socket: socket, port: port}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, %{socket: socket} = state) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        spawn(fn -> handle_http(client) end)
        send(self(), :accept)
        {:noreply, state}

      {:error, _} ->
        send(self(), :accept)
        {:noreply, state}
    end
  end

  defp handle_http(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, {:http_request, method, {:abs_path, path}, _version}} ->
        consume_headers(socket)
        path_string = to_string(path)
        handle_route(socket, %{method: method, path: path_string})

      {:ok, {:http_request, method, :*, _version}} ->
        consume_headers(socket)
        handle_route(socket, %{method: method, path: "*"})

      {:ok, _other} ->
        :gen_tcp.close(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp consume_headers(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} ->
        :ok

      {:ok, {:http_header, _, _name, _, _value}} ->
        consume_headers(socket)

      _ ->
        :ok
    end
  end

  defp handle_route(socket, %{method: :GET, path: "/"}), do: serve_html(socket)
  defp handle_route(socket, %{method: :GET, path: "/metrics"}), do: serve_metrics(socket)
  defp handle_route(socket, %{method: :GET, path: "/stream"}), do: serve_sse(socket)
  defp handle_route(socket, _), do: serve_404(socket)

  defp serve_html(socket) do
    html = dashboard_html()

    response = """
    HTTP/1.1 200 OK\r
    Content-Type: text/html; charset=utf-8\r
    Content-Length: #{byte_size(html)}\r
    \r
    #{html}
    """

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp serve_metrics(socket) do
    metrics = %{
      queues: MalachiMQ.Metrics.get_all_metrics(),
      system: MalachiMQ.Metrics.get_system_metrics()
    }

    json = Jason.encode!(metrics)

    response = """
    HTTP/1.1 200 OK\r
    Content-Type: application/json\r
    Access-Control-Allow-Origin: *\r
    Content-Length: #{byte_size(json)}\r
    \r
    #{json}
    """

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp serve_sse(socket) do
    response = """
    HTTP/1.1 200 OK\r
    Content-Type: text/event-stream\r
    Cache-Control: no-cache\r
    Connection: keep-alive\r
    Access-Control-Allow-Origin: *\r
    \r
    """

    :gen_tcp.send(socket, response)
    :inet.setopts(socket, packet: :raw)

    stream_metrics(socket)
  end

  defp stream_metrics(socket) do
    metrics = %{
      queues: MalachiMQ.Metrics.get_all_metrics(),
      system: MalachiMQ.Metrics.get_system_metrics()
    }

    json = Jason.encode!(metrics)
    event = "data: #{json}\n\n"

    update_interval = Application.get_env(:malachimq, :dashboard_update_interval_ms, 1000)

    case :gen_tcp.send(socket, event) do
      :ok ->
        Process.sleep(update_interval)
        stream_metrics(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp serve_404(socket) do
    response = """
    HTTP/1.1 404 Not Found\r
    Content-Type: text/plain\r
    Content-Length: 9\r
    \r
    Not Found
    """

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp dashboard_html do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>MalachiMQ Dashboard</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, sans-serif;
          background: #0a0e27;
          color: #e0e0e0;
          padding: 20px;
        }
        h1 { color: #00d9ff; margin-bottom: 20px; }
        .card {
          background: #1a1f3a;
          border: 1px solid #2a3f5f;
          border-radius: 8px;
          padding: 20px;
          margin-bottom: 20px;
        }
        .metric { display: flex; justify-content: space-between; padding: 8px 0; }
        .metric-value { color: #00ff88; font-family: monospace; }
      </style>
    </head>
    <body>
      <h1>🚀 MalachiMQ Dashboard</h1>
      <div class="card">
        <h2>System Status</h2>
        <div class="metric">
          <span>Processes:</span>
          <span class="metric-value" id="processes">-</span>
        </div>
        <div class="metric">
          <span>Memory:</span>
          <span class="metric-value" id="memory">-</span>
        </div>
      </div>
      <div class="card">
        <h2>Queues</h2>
        <div id="queues">Loading...</div>
      </div>
      <script>
        const source = new EventSource('/stream');
        source.onmessage = (event) => {
          const data = JSON.parse(event.data);
          document.getElementById('processes').textContent = data.system.process_count;
          document.getElementById('memory').textContent = data.system.memory.total_mb.toFixed(2) + ' MB';

          const queuesHtml = data.queues.map(q =>
            `<div style="padding: 10px; border-left: 3px solid #00d9ff; margin: 10px 0;">
              <strong>${q.queue}</strong><br>
              <span style="color: #888;">Consumers:</span> ${q.queue_stats.consumers} |
              <span style="color: #00ff88;">✓ Acked:</span> ${q.acked || 0} |
              <span style="color: #ff6b6b;">✗ Nacked:</span> ${q.nacked || 0} |
              <span style="color: #ffd93d;">⏳ Pending:</span> ${q.pending_ack || 0} |
              <span style="color: #6bcfff;">↻ Retried:</span> ${q.retried || 0} |
              <span style="color: #ff4757;">☠ DLQ:</span> ${q.dead_lettered || 0}<br>
              <span style="color: #888;">Processed:</span> ${q.processed} |
              <span style="color: #888;">Buffered:</span> ${q.queue_stats.buffered} |
              <span style="color: #888;">Latency:</span> ${q.latency_us.avg ? (q.latency_us.avg/1000).toFixed(2) + 'ms' : '-'}
            </div>`
          ).join('');

          document.getElementById('queues').innerHTML = queuesHtml || 'No queues';
        };
      </script>
    </body>
    </html>
    """
  end
end
