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
