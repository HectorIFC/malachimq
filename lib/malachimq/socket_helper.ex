defmodule MalachiMQ.SocketHelper do
  @moduledoc """
  Helper module to abstract socket operations for both TCP and TLS transports.
  Provides a unified interface for socket operations regardless of transport type.
  """

  @doc """
  Receives data from socket with timeout.
  Works with both :gen_tcp and :ssl transports.
  """
  def socket_recv(socket, length, timeout, :gen_tcp) do
    :gen_tcp.recv(socket, length, timeout)
  end

  def socket_recv(socket, length, timeout, :ssl) do
    :ssl.recv(socket, length, timeout)
  end

  @doc """
  Sends data through socket.
  Works with both :gen_tcp and :ssl transports.
  """
  def socket_send(socket, data, :gen_tcp) do
    :gen_tcp.send(socket, data)
  end

  def socket_send(socket, data, :ssl) do
    :ssl.send(socket, data)
  end

  @doc """
  Closes socket connection.
  Works with both :gen_tcp and :ssl transports.
  Returns :ok on success or {:error, reason} on failure.
  """
  def socket_close(socket, :gen_tcp) do
    :gen_tcp.close(socket)
  rescue
    _ -> {:error, :invalid_socket}
  catch
    _, _ -> {:error, :invalid_socket}
  end

  def socket_close(socket, :ssl) do
    :ssl.close(socket)
  rescue
    _ -> {:error, :invalid_socket}
  catch
    _, _ -> {:error, :invalid_socket}
  end

  @doc """
  Sets socket options.
  Works with both :gen_tcp and :ssl transports.
  """
  def socket_setopts(socket, opts, :gen_tcp) do
    :inet.setopts(socket, opts)
  end

  def socket_setopts(socket, opts, :ssl) do
    :ssl.setopts(socket, opts)
  end

  @doc """
  Gets socket peer information.
  Works with both :gen_tcp and :ssl transports.
  """
  def socket_peername(socket, :gen_tcp) do
    :inet.peername(socket)
  end

  def socket_peername(socket, :ssl) do
    :ssl.peername(socket)
  end
end
