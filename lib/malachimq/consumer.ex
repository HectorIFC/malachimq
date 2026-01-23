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

    config = MalachiMQ.QueueConfig.get_config(state.queue_name)

    try do
      result = state.callback.(message)

      latency = System.monotonic_time(:microsecond) - message.timestamp
      MalachiMQ.Metrics.record_latency(state.queue_name, latency)
      MalachiMQ.Metrics.increment_processed(state.queue_name)

      # Only handle acks for at_least_once delivery mode
      if config.delivery_mode == :at_least_once and Process.whereis(MalachiMQ.AckManager) do
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

        # Only handle nacks for at_least_once delivery mode
        if config.delivery_mode == :at_least_once and Process.whereis(MalachiMQ.AckManager) do
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
