defmodule MalachiMQ.SocketHelperTest do
  use ExUnit.Case, async: true

  describe "socket_send/3" do
    test "sends data through gen_tcp socket" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, packet: :line, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        {:ok, _data} = :gen_tcp.recv(socket, 0, 1000)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :line, active: false])
      
      assert :ok = MalachiMQ.SocketHelper.socket_send(client, "test\n", :gen_tcp)
      
      :gen_tcp.close(client)
      :gen_tcp.close(listen_socket)
    end

    test "handles SSL socket send" do
      # Test that SSL variant exists and can be called
      # We can't easily test real SSL without certificates, but we can verify the function exists
      assert function_exported?(MalachiMQ.SocketHelper, :socket_send, 3)
    end
  end

  describe "socket_recv/4" do
    test "receives data from gen_tcp socket" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, packet: :line, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      test_pid = self()
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        :gen_tcp.send(socket, "hello\n")
        send(test_pid, :sent)
        :timer.sleep(100)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :line, active: false])
      
      assert_receive :sent, 1000
      assert {:ok, data} = MalachiMQ.SocketHelper.socket_recv(client, 0, 1000, :gen_tcp)
      assert data == "hello\n"
      
      :gen_tcp.close(client)
      :gen_tcp.close(listen_socket)
    end

    test "handles timeout on recv" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, _socket} = :gen_tcp.accept(listen_socket)
        # Don't send anything - let it timeout
        :timer.sleep(500)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      
      result = MalachiMQ.SocketHelper.socket_recv(client, 0, 100, :gen_tcp)
      assert {:error, :timeout} = result
      
      :gen_tcp.close(client)
      :gen_tcp.close(listen_socket)
    end

    test "SSL recv function exists" do
      assert function_exported?(MalachiMQ.SocketHelper, :socket_recv, 4)
    end
  end

  describe "socket_close/2" do
    test "closes gen_tcp socket" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        :timer.sleep(100)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      
      assert :ok = MalachiMQ.SocketHelper.socket_close(client, :gen_tcp)
      
      :gen_tcp.close(listen_socket)
    end

    test "handles invalid gen_tcp socket gracefully" do
      result = MalachiMQ.SocketHelper.socket_close(:invalid_socket, :gen_tcp)
      assert result in [:ok, {:error, :invalid_socket}]
    end

    test "handles invalid SSL socket gracefully" do
      result = MalachiMQ.SocketHelper.socket_close(:invalid_ssl_socket, :ssl)
      assert {:error, :invalid_socket} = result
    end

    test "handles already closed socket" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      :gen_tcp.close(client)
      
      # Try closing again
      result = MalachiMQ.SocketHelper.socket_close(client, :gen_tcp)
      assert result in [:ok, {:error, :invalid_socket}]
      
      :gen_tcp.close(listen_socket)
    end
  end

  describe "socket_setopts/3" do
    test "sets options on gen_tcp socket" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        :timer.sleep(100)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      
      assert :ok = MalachiMQ.SocketHelper.socket_setopts(client, [active: false], :gen_tcp)
      
      :gen_tcp.close(client)
      :gen_tcp.close(listen_socket)
    end

    test "sets multiple options" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        :timer.sleep(100)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      
      result = MalachiMQ.SocketHelper.socket_setopts(client, [active: false, nodelay: true], :gen_tcp)
      assert :ok = result
      
      :gen_tcp.close(client)
      :gen_tcp.close(listen_socket)
    end

    test "SSL setopts function exists" do
      assert function_exported?(MalachiMQ.SocketHelper, :socket_setopts, 3)
    end
  end

  describe "socket_peername/2" do
    test "gets peer info from gen_tcp socket" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        :timer.sleep(100)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      
      assert {:ok, {_ip, _port}} = MalachiMQ.SocketHelper.socket_peername(client, :gen_tcp)
      
      :gen_tcp.close(client)
      :gen_tcp.close(listen_socket)
    end

    test "returns IPv4 address format" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)
      
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        :timer.sleep(100)
        :gen_tcp.close(socket)
      end)
      
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      
      {:ok, {ip, port_num}} = MalachiMQ.SocketHelper.socket_peername(client, :gen_tcp)
      
      # Verify it's a valid IPv4 tuple
      assert is_tuple(ip)
      assert tuple_size(ip) == 4
      assert is_integer(port_num)
      assert port_num > 0
      
      :gen_tcp.close(client)
      :gen_tcp.close(listen_socket)
    end

    test "SSL peername function exists" do
      assert function_exported?(MalachiMQ.SocketHelper, :socket_peername, 2)
    end
  end

  describe "error handling" do
    test "handles errors on invalid socket operations" do
      # Test that error paths are handled
      invalid_socket = :not_a_real_socket
      
      # These should return errors or handle gracefully
      result = MalachiMQ.SocketHelper.socket_close(invalid_socket, :gen_tcp)
      assert result in [:ok, {:error, :invalid_socket}]
    end
  end
end
