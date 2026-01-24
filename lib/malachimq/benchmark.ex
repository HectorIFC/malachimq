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
    rate = if duration > 0, do: round(count / (duration / 1000)), else: count
    Logger.info(I18n.t(:consumers_rate, rate: rate))

    :erlang.garbage_collect()
    memory_mb = :erlang.memory(:total) / 1_048_576
    Logger.info(I18n.t(:total_memory, memory: Float.round(memory_mb, 2)))
    memory_per = if count > 0, do: round(memory_mb * 1024 / count), else: 0
    Logger.info(I18n.t(:memory_per_consumer, memory: memory_per))
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
    rate = if duration > 0, do: round(count / (duration / 1000)), else: count
    Logger.info(I18n.t(:messages_rate, rate: rate))
  end

  def system_info do
    info = %{
      schedulers: :erlang.system_info(:schedulers_online),
      processes: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      memory_mb: :erlang.memory(:total) / 1_048_576,
      ets_tables: length(:ets.all()),
      ets_limit: :erlang.system_info(:ets_limit)
    }

    Logger.info(I18n.t(:system_info))
    Logger.info(I18n.t(:system_schedulers, schedulers: info.schedulers))
    Logger.info(I18n.t(:system_processes, processes: info.processes, limit: info.process_limit))
    Logger.info(I18n.t(:system_memory, memory: Float.round(info.memory_mb, 2)))
    Logger.info(I18n.t(:system_ets_tables, tables: info.ets_tables, limit: info.ets_limit))

    info
  end
end
