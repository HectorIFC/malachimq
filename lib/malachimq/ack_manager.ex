defmodule MalachiMQ.AckManager do
  @moduledoc """
  Manages message acknowledgments.
  Tracks pending messages and allows redelivery in case of failure/timeout.
  """
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  @pending_table :malachimq_pending_acks
  @default_timeout_ms 30_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registers a message as pending acknowledgment.
  Called by Queue before sending to consumer.
  """
  def track_message(message_id, queue_name, consumer_pid, message) do
    timeout = Application.get_env(:malachimq, :ack_timeout_ms, @default_timeout_ms)
    expires_at = System.monotonic_time(:millisecond) + timeout

    entry = %{
      message_id: message_id,
      queue_name: queue_name,
      consumer_pid: consumer_pid,
      message: message,
      sent_at: System.monotonic_time(:millisecond),
      expires_at: expires_at,
      attempts: 1
    }

    :ets.insert(@pending_table, {message_id, entry})
    :ok
  end

  @doc """
  Consumer acknowledges successful processing.
  Removes the message from the pending list.
  """
  def ack(message_id) do
    case :ets.lookup(@pending_table, message_id) do
      [{^message_id, entry}] ->
        :ets.delete(@pending_table, message_id)
        MalachiMQ.Metrics.increment_acked(entry.queue_name)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Consumer rejects message.
  Can requeue (requeue: true) or discard.
  """
  def nack(message_id, opts \\ []) do
    requeue = Keyword.get(opts, :requeue, true)

    case :ets.lookup(@pending_table, message_id) do
      [{^message_id, entry}] ->
        :ets.delete(@pending_table, message_id)
        MalachiMQ.Metrics.increment_nacked(entry.queue_name)

        if requeue do
          MalachiMQ.Queue.enqueue(
            entry.queue_name,
            entry.message.payload,
            Map.put(entry.message.headers, "_retry_count", entry.attempts)
          )
        end

        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Checks the status of a specific message.
  """
  def get_status(message_id) do
    case :ets.lookup(@pending_table, message_id) do
      [{^message_id, entry}] ->
        elapsed = System.monotonic_time(:millisecond) - entry.sent_at
        {:pending, Map.put(entry, :elapsed_ms, elapsed)}

      [] ->
        :acknowledged_or_unknown
    end
  end

  @doc """
  Counts messages pending acknowledgment per queue.
  """
  def pending_count(queue_name) do
    :ets.foldl(
      fn {_id, entry}, acc ->
        if entry.queue_name == queue_name, do: acc + 1, else: acc
      end,
      0,
      @pending_table
    )
  end

  @doc """
  Lists all pending messages from a queue.
  """
  def list_pending(queue_name) do
    now = System.monotonic_time(:millisecond)

    :ets.foldl(
      fn {_id, entry}, acc ->
        if entry.queue_name == queue_name do
          [Map.put(entry, :elapsed_ms, now - entry.sent_at) | acc]
        else
          acc
        end
      end,
      [],
      @pending_table
    )
  end

  @doc """
  Returns general statistics of the ACK system.
  """
  def stats do
    now = System.monotonic_time(:millisecond)

    :ets.foldl(
      fn {_id, entry}, acc ->
        queue = entry.queue_name
        elapsed = now - entry.sent_at

        queue_stats = Map.get(acc, queue, %{count: 0, oldest_ms: 0, newest_ms: elapsed})

        updated = %{
          count: queue_stats.count + 1,
          oldest_ms: max(queue_stats.oldest_ms, elapsed),
          newest_ms: min(queue_stats.newest_ms, elapsed)
        }

        Map.put(acc, queue, updated)
      end,
      %{},
      @pending_table
    )
  end

  @impl true
  def init(:ok) do
    :ets.new(@pending_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_timeout_check()

    Logger.info(I18n.t(:ack_manager_started, timeout: @default_timeout_ms))
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_timeouts, state) do
    expired_count = check_expired_messages()

    if expired_count > 0 do
      Logger.warning(I18n.t(:messages_expired, count: expired_count))
    end

    schedule_timeout_check()
    {:noreply, state}
  end

  defp schedule_timeout_check do
    interval = Application.get_env(:malachimq, :ack_check_interval_ms, 5_000)
    Process.send_after(self(), :check_timeouts, interval)
  end

  defp check_expired_messages do
    now = System.monotonic_time(:millisecond)
    max_retries = Application.get_env(:malachimq, :max_retries, 3)

    expired =
      :ets.foldl(
        fn {message_id, entry}, acc ->
          if entry.expires_at < now do
            [{message_id, entry} | acc]
          else
            acc
          end
        end,
        [],
        @pending_table
      )

    Enum.each(expired, fn {message_id, entry} ->
      :ets.delete(@pending_table, message_id)

      if entry.attempts < max_retries do
        Logger.warning(I18n.t(:message_expired_retry, id: message_id, attempt: entry.attempts, max: max_retries))

        MalachiMQ.Queue.enqueue(
          entry.queue_name,
          entry.message.payload,
          Map.put(entry.message.headers, "_retry_count", entry.attempts + 1)
        )

        MalachiMQ.Metrics.increment_retried(entry.queue_name)
      else
        Logger.error(I18n.t(:message_failed_dlq, id: message_id, max: max_retries))

        MalachiMQ.Metrics.increment_dead_lettered(entry.queue_name)
      end
    end)

    length(expired)
  end
end
