defmodule MalachiMQ.QueueConfig do
  @moduledoc """
  Manages queue configuration and metadata.
  Stores delivery mode, max retries, and DLQ settings per queue.
  """
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  @config_table :malachimq_queue_config

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Creates or updates queue configuration.
  Returns {:ok, config} or {:error, reason}.
  """
  def create_queue(queue_name, opts \\ []) do
    delivery_mode = Keyword.get(opts, :delivery_mode, get_default_delivery_mode())
    max_retries = Keyword.get(opts, :max_retries, 3)
    dlq_enabled = Keyword.get(opts, :dlq_enabled, true)

    unless delivery_mode in [:at_least_once, :at_most_once] do
      {:error, :invalid_delivery_mode}
    else
      config = %{
        queue_name: queue_name,
        delivery_mode: delivery_mode,
        max_retries: max_retries,
        dlq_enabled: dlq_enabled,
        created_at: System.system_time(:second)
      }

      case :ets.lookup(@config_table, queue_name) do
        [] ->
          :ets.insert(@config_table, {queue_name, config})
          Logger.info(I18n.t(:queue_created, queue: queue_name, mode: delivery_mode))
          {:ok, config}

        [{^queue_name, _existing}] ->
          {:error, :queue_already_exists}
      end
    end
  end

  @doc """
  Gets queue configuration.
  Returns config map or creates default if not exists.
  """
  def get_config(queue_name) do
    case :ets.lookup(@config_table, queue_name) do
      [{^queue_name, config}] ->
        config

      [] ->
        # Create implicit queue with defaults
        delivery_mode = get_default_delivery_mode()

        config = %{
          queue_name: queue_name,
          delivery_mode: delivery_mode,
          max_retries: 3,
          dlq_enabled: true,
          created_at: System.system_time(:second),
          implicit: true
        }

        :ets.insert(@config_table, {queue_name, config})
        Logger.warning(I18n.t(:queue_created_implicitly, queue: queue_name, mode: delivery_mode))
        config
    end
  end

  @doc """
  Deletes queue configuration.
  Returns :ok or {:error, reason}.
  """
  def delete_queue(queue_name, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    case :ets.lookup(@config_table, queue_name) do
      [] ->
        {:error, :queue_not_found}

      [{^queue_name, _config}] ->
        unless force do
          stats = MalachiMQ.Queue.get_stats(queue_name)

          cond do
            stats.consumers > 0 ->
              {:error, :queue_has_active_consumers}

            stats.buffered > 0 ->
              {:error, :queue_has_buffered_messages}

            true ->
              :ets.delete(@config_table, queue_name)
              Logger.info(I18n.t(:queue_deleted, queue: queue_name))
              :ok
          end
        else
          :ets.delete(@config_table, queue_name)
          Logger.info(I18n.t(:queue_deleted, queue: queue_name))
          :ok
        end
    end
  end

  @doc """
  Lists all configured queues.
  """
  def list_queues do
    :ets.tab2list(@config_table)
    |> Enum.map(fn {_name, config} -> config end)
    |> Enum.sort_by(& &1.created_at)
  end

  @doc """
  Checks if queue exists.
  """
  def exists?(queue_name) do
    case :ets.lookup(@config_table, queue_name) do
      [] -> false
      _ -> true
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@config_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    Logger.info(I18n.t(:queue_config_started))
    {:ok, %{}}
  end

  defp get_default_delivery_mode do
    mode_str = Application.get_env(:malachimq, :default_delivery_mode, "at_least_once")

    case mode_str do
      "at_most_once" -> :at_most_once
      _ -> :at_least_once
    end
  end
end
