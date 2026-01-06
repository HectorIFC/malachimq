defmodule MalachiMQ.Application do
  @moduledoc """
  Main application supervisor for MalachiMQ.

  Coordinates all core services including:
  - Queue management and partitioning
  - TCP/TLS server for client connections
  - Metrics collection and monitoring
  - Authentication and authorization
  - Web dashboard
  - Message acknowledgment tracking
  """
  use Application

  def start(_type, _args) do
    port = Application.get_env(:malachimq, :tcp_port, 4040)
    dashboard_port = Application.get_env(:malachimq, :dashboard_port, 4041)

    available_schedulers = System.schedulers_online()
    configured_schedulers = Application.get_env(:malachimq, :schedulers, available_schedulers)
    schedulers_to_use = min(configured_schedulers, available_schedulers)

    :erlang.system_flag(:schedulers_online, schedulers_to_use)

    children = [
      {Registry, keys: :unique, name: MalachiMQ.QueueRegistry, partitions: System.schedulers_online()},
      {DynamicSupervisor, name: MalachiMQ.QueueSupervisor, strategy: :one_for_one, max_children: 100_000},
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
