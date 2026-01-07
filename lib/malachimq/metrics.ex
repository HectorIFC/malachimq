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
