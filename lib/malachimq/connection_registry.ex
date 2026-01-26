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
    ip = get_peer_address(socket, transport)
    :ets.insert(@table, {pid, socket, transport, System.monotonic_time(:millisecond), ip, :unknown, nil})
    Process.monitor(pid)
    :ok
  end

  @doc """
  Update connection type (producer or consumer) and associated queue.
  """
  def set_connection_type(pid, type, queue_name \\ nil)
      when type in [:producer, :consumer, :channel_publisher, :channel_subscriber] do
    case :ets.lookup(@table, pid) do
      [{^pid, socket, transport, connected_at, ip, _old_type, _old_queue}] ->
        :ets.insert(@table, {pid, socket, transport, connected_at, ip, type, queue_name})
        :ok

      [] ->
        {:error, :not_found}
    end
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
  Get list of producers with their IPs for a specific queue.
  """
  def list_producers_by_queue(queue_name) do
    :ets.tab2list(@table)
    |> Enum.filter(fn
      {_pid, _socket, _transport, _connected_at, _ip, type, queue} ->
        type == :producer and queue == queue_name

      _ ->
        false
    end)
    |> Enum.map(fn {pid, _socket, _transport, connected_at, ip, _type, _queue} ->
      %{
        pid: inspect(pid),
        ip: ip,
        connected_at: connected_at
      }
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc """
  Get list of consumers with their IPs for a specific queue.
  """
  def list_consumers_by_queue(queue_name) do
    :ets.tab2list(@table)
    |> Enum.filter(fn
      {_pid, _socket, _transport, _connected_at, _ip, type, queue} ->
        type == :consumer and queue == queue_name

      _ ->
        false
    end)
    |> Enum.map(fn {pid, _socket, _transport, connected_at, ip, _type, _queue} ->
      %{
        pid: inspect(pid),
        ip: ip,
        connected_at: connected_at
      }
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc """
  Get list of subscribers with their IPs for a specific channel.
  """
  def list_subscribers_by_channel(channel_name) do
    :ets.tab2list(@table)
    |> Enum.filter(fn
      {_pid, _socket, _transport, _connected_at, _ip, type, channel} ->
        type == :channel_subscriber and channel == channel_name

      _ ->
        false
    end)
    |> Enum.map(fn {pid, _socket, _transport, connected_at, ip, _type, _channel} ->
      %{
        pid: inspect(pid),
        ip: ip,
        connected_at: connected_at
      }
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc """
  Get list of producers with their IPs.
  """
  def list_producers do
    :ets.tab2list(@table)
    |> Enum.filter(fn
      {_pid, _socket, _transport, _connected_at, _ip, type, _queue} -> type == :producer
      {_pid, _socket, _transport, _connected_at, _ip, type} -> type == :producer
    end)
    |> Enum.map(fn
      {pid, _socket, _transport, connected_at, ip, _type, _queue} ->
        %{
          pid: inspect(pid),
          ip: ip,
          connected_at: connected_at
        }

      {pid, _socket, _transport, connected_at, ip, _type} ->
        %{
          pid: inspect(pid),
          ip: ip,
          connected_at: connected_at
        }
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc """
  Get list of consumers with their IPs.
  """
  def list_consumers do
    :ets.tab2list(@table)
    |> Enum.filter(fn
      {_pid, _socket, _transport, _connected_at, _ip, type, _queue} -> type == :consumer
      {_pid, _socket, _transport, _connected_at, _ip, type} -> type == :consumer
    end)
    |> Enum.map(fn
      {pid, _socket, _transport, connected_at, ip, _type, _queue} ->
        %{
          pid: inspect(pid),
          ip: ip,
          connected_at: connected_at
        }

      {pid, _socket, _transport, connected_at, ip, _type} ->
        %{
          pid: inspect(pid),
          ip: ip,
          connected_at: connected_at
        }
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc """
  Close all active connections gracefully.
  Called during application shutdown.
  """
  def close_all do
    connections = :ets.tab2list(@table)
    Logger.info(I18n.t(:closing_connections, count: length(connections)))

    for entry <- connections do
      {pid, socket, transport, _connected_at, _ip, _type} =
        case entry do
          {p, s, t, c, i, ty, _q} -> {p, s, t, c, i, ty}
          {p, s, t, c, i, ty} -> {p, s, t, c, i, ty}
        end

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

  # Private helper functions

  defp get_peer_address(socket, transport) do
    case transport do
      :ssl ->
        case :ssl.peername(socket) do
          {:ok, {address, _port}} -> format_ip(address)
          {:error, _} -> "unknown"
        end

      :gen_tcp ->
        case :inet.peername(socket) do
          {:ok, {address, _port}} -> format_ip(address)
          {:error, _} -> "unknown"
        end
    end
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp format_ip({a, b, c, d, e, f, g, h}),
    do:
      "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}:#{Integer.to_string(d, 16)}:#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"

  defp format_ip(_), do: "unknown"
end
