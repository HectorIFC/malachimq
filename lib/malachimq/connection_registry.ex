defmodule MalachiMQ.ConnectionRegistry do
  @moduledoc """
  Tracks active client connections for graceful shutdown.
  Uses ETS for fast concurrent access.
  """
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  @table :malachimq_connections

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Register a client connection with its socket and transport.
  """
  def register(pid, socket, transport) do
    :ets.insert(@table, {pid, socket, transport, System.monotonic_time(:millisecond)})
    Process.monitor(pid)
    :ok
  end

  @doc """
  Unregister a client connection.
  """
  def unregister(pid) do
    :ets.delete(@table, pid)
    :ok
  end

  @doc """
  Get count of active connections.
  """
  def count do
    :ets.info(@table, :size)
  end

  @doc """
  Close all active connections gracefully.
  Called during application shutdown.
  """
  def close_all do
    connections = :ets.tab2list(@table)
    Logger.info(I18n.t(:closing_connections, count: length(connections)))

    for {pid, socket, transport, _connected_at} <- connections do
      # Send shutdown notification to client
      try do
        shutdown_msg = Jason.encode!(%{"shutdown" => true, "reason" => "server_restart"})

        case transport do
          :ssl -> :ssl.send(socket, shutdown_msg <> "\n")
          :gen_tcp -> :gen_tcp.send(socket, shutdown_msg <> "\n")
        end

        # Give client time to receive the message
        Process.sleep(50)

        # Close the socket
        case transport do
          :ssl -> :ssl.close(socket)
          :gen_tcp -> :gen_tcp.close(socket)
        end
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end

      # Stop the handler process
      Process.exit(pid, :shutdown)
    end

    :ets.delete_all_objects(@table)
    :ok
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    unregister(pid)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
