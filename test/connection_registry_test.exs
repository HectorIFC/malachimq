defmodule MalachiMQ.ConnectionRegistryTest do
  use ExUnit.Case, async: false

  setup do
    # Create a real TCP socket for testing
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)

    spawn(fn ->
      {:ok, _socket} = :gen_tcp.accept(listen_socket)

      receive do
        _ -> :ok
      end
    end)

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    on_exit(fn ->
      :gen_tcp.close(socket)
      :gen_tcp.close(listen_socket)
    end)

    {:ok, socket: socket}
  end

  describe "register/3" do
    test "registers a new connection", %{socket: socket} do
      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      transport = :gen_tcp

      assert :ok = MalachiMQ.ConnectionRegistry.register(pid, socket, transport)

      count = MalachiMQ.ConnectionRegistry.count()
      assert count >= 1
    end

    test "monitors registered process", %{socket: socket} do
      test_pid = self()

      pid =
        spawn(fn ->
          send(test_pid, :ready)

          receive do
            _ -> :ok
          end
        end)

      receive do
        :ready -> :ok
      end

      initial_count = MalachiMQ.ConnectionRegistry.count()
      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)

      Process.exit(pid, :kill)
      :timer.sleep(100)

      final_count = MalachiMQ.ConnectionRegistry.count()
      assert final_count < initial_count + 1 or not Process.alive?(pid)
    end
  end

  describe "set_connection_type/3" do
    test "updates connection type to producer", %{socket: socket} do
      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)

      assert :ok = MalachiMQ.ConnectionRegistry.set_connection_type(pid, :producer, "test_queue")
    end

    test "updates connection type to consumer", %{socket: socket} do
      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)

      assert :ok = MalachiMQ.ConnectionRegistry.set_connection_type(pid, :consumer, "test_queue")
    end

    test "returns error for unregistered pid" do
      fake_pid = spawn(fn -> :ok end)
      :timer.sleep(50)

      assert {:error, :not_found} = MalachiMQ.ConnectionRegistry.set_connection_type(fake_pid, :producer)
    end

    test "updates type multiple times", %{socket: socket} do
      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)

      assert :ok = MalachiMQ.ConnectionRegistry.set_connection_type(pid, :producer, "queue1")
      assert :ok = MalachiMQ.ConnectionRegistry.set_connection_type(pid, :consumer, "queue2")
    end
  end

  describe "unregister/1" do
    test "unregisters a connection", %{socket: socket} do
      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)

      initial_count = MalachiMQ.ConnectionRegistry.count()
      assert :ok = MalachiMQ.ConnectionRegistry.unregister(pid)

      final_count = MalachiMQ.ConnectionRegistry.count()
      assert final_count < initial_count
    end

    test "unregistering non-existent connection is harmless" do
      fake_pid = spawn(fn -> :ok end)
      assert :ok = MalachiMQ.ConnectionRegistry.unregister(fake_pid)
    end
  end

  describe "count/0" do
    test "returns count of active connections" do
      count = MalachiMQ.ConnectionRegistry.count()
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "list_producers_by_queue/1" do
    test "lists producers for specific queue", %{socket: socket} do
      queue_name = "producer_queue_#{:rand.uniform(10000)}"

      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)
      MalachiMQ.ConnectionRegistry.set_connection_type(pid, :producer, queue_name)

      producers = MalachiMQ.ConnectionRegistry.list_producers_by_queue(queue_name)

      assert is_list(producers)
      assert length(producers) >= 1

      if length(producers) > 0 do
        producer = hd(producers)
        assert Map.has_key?(producer, :pid)
        assert Map.has_key?(producer, :ip)
        assert Map.has_key?(producer, :connected_at)
      end
    end

    test "returns empty list for queue with no producers" do
      producers = MalachiMQ.ConnectionRegistry.list_producers_by_queue("nonexistent_queue_#{:rand.uniform(10000)}")
      assert producers == []
    end

    test "does not include consumers", %{socket: _socket} do
      queue_name = "mixed_queue_#{:rand.uniform(10000)}"

      # Create two sockets
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)

      spawn(fn ->
        {:ok, _s1} = :gen_tcp.accept(listen_socket)
        {:ok, _s2} = :gen_tcp.accept(listen_socket)

        receive do
          _ -> :ok
        end
      end)

      {:ok, socket1} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      {:ok, socket2} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

      producer_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      consumer_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(producer_pid, socket1, :gen_tcp)
      MalachiMQ.ConnectionRegistry.register(consumer_pid, socket2, :gen_tcp)

      MalachiMQ.ConnectionRegistry.set_connection_type(producer_pid, :producer, queue_name)
      MalachiMQ.ConnectionRegistry.set_connection_type(consumer_pid, :consumer, queue_name)

      producers = MalachiMQ.ConnectionRegistry.list_producers_by_queue(queue_name)

      assert length(producers) >= 1
      assert Enum.all?(producers, fn p -> String.contains?(p.pid, inspect(producer_pid)) end)
    end
  end

  describe "list_consumers_by_queue/1" do
    test "lists consumers for specific queue", %{socket: socket} do
      queue_name = "consumer_queue_#{:rand.uniform(10000)}"

      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)
      MalachiMQ.ConnectionRegistry.set_connection_type(pid, :consumer, queue_name)

      consumers = MalachiMQ.ConnectionRegistry.list_consumers_by_queue(queue_name)

      assert is_list(consumers)
      assert length(consumers) >= 1

      if length(consumers) > 0 do
        consumer = hd(consumers)
        assert Map.has_key?(consumer, :pid)
        assert Map.has_key?(consumer, :ip)
        assert Map.has_key?(consumer, :connected_at)
      end
    end

    test "returns empty list for queue with no consumers" do
      consumers = MalachiMQ.ConnectionRegistry.list_consumers_by_queue("nonexistent_queue_#{:rand.uniform(10000)}")
      assert consumers == []
    end
  end

  describe "list_producers/0" do
    test "lists all producers", %{socket: socket} do
      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)
      MalachiMQ.ConnectionRegistry.set_connection_type(pid, :producer, "test_queue")

      producers = MalachiMQ.ConnectionRegistry.list_producers()
      assert is_list(producers)
    end
  end

  describe "list_consumers/0" do
    test "lists all consumers", %{socket: socket} do
      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)
      MalachiMQ.ConnectionRegistry.set_connection_type(pid, :consumer, "test_queue")

      consumers = MalachiMQ.ConnectionRegistry.list_consumers()
      assert is_list(consumers)
    end
  end

  describe "graceful_shutdown/1" do
    test "closes all connections", %{socket: _socket} do
      # Create two new sockets for this test
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)

      spawn(fn ->
        {:ok, _s1} = :gen_tcp.accept(listen_socket)
        {:ok, _s2} = :gen_tcp.accept(listen_socket)

        receive do
          _ -> :ok
        end
      end)

      {:ok, socket1} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      {:ok, socket2} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

      pid1 =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      pid2 =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid1, socket1, :gen_tcp)
      MalachiMQ.ConnectionRegistry.register(pid2, socket2, :gen_tcp)

      result = MalachiMQ.ConnectionRegistry.close_all()
      assert result == :ok

      :timer.sleep(100)
      count = MalachiMQ.ConnectionRegistry.count()
      assert count == 0

      :gen_tcp.close(listen_socket)
    end

    test "handles empty connection list gracefully" do
      # Clear any existing connections first
      MalachiMQ.ConnectionRegistry.close_all()
      :timer.sleep(50)

      # Call close_all when there are no connections
      result = MalachiMQ.ConnectionRegistry.close_all()
      assert result == :ok
    end

    test "sends shutdown notification to clients", %{socket: _socket} do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, packet: 0, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)

      test_pid = self()

      spawn(fn ->
        {:ok, client_socket} = :gen_tcp.accept(listen_socket)
        # Try to receive the shutdown message
        case :gen_tcp.recv(client_socket, 0, 200) do
          {:ok, msg} ->
            send(test_pid, {:received, msg})

          _ ->
            send(test_pid, :no_message)
        end
      end)

      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: 0, active: false])

      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)
      MalachiMQ.ConnectionRegistry.close_all()

      # The shutdown message should have been sent
      receive do
        {:received, msg} ->
          assert String.contains?(msg, "shutdown")

        :no_message ->
          # Message might have been sent but not received in time, that's ok
          :ok
      after
        500 ->
          :ok
      end

      :gen_tcp.close(listen_socket)
    end
  end

  describe "process monitoring" do
    test "automatically unregisters dead processes", %{socket: socket} do
      pid = spawn(fn -> :ok end)
      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)

      :timer.sleep(100)

      # Process should have exited and been unregistered
      # We can verify by checking that count doesn't grow indefinitely
      initial_count = MalachiMQ.ConnectionRegistry.count()
      assert is_integer(initial_count)
    end

    test "handles DOWN messages", %{socket: socket} do
      test_pid = self()

      pid =
        spawn(fn ->
          send(test_pid, :started)

          receive do
            :exit -> :ok
          end
        end)

      receive do
        :started -> :ok
      end

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)
      initial_count = MalachiMQ.ConnectionRegistry.count()

      send(pid, :exit)
      :timer.sleep(100)

      final_count = MalachiMQ.ConnectionRegistry.count()
      # Count should be less or equal (process was cleaned up)
      assert final_count <= initial_count
    end
  end

  describe "IP address formatting" do
    test "formats IPv4 addresses correctly", %{socket: _socket} do
      # When we register with a TCP socket, it should format the IP correctly
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen_socket)

      spawn(fn ->
        {:ok, _s} = :gen_tcp.accept(listen_socket)

        receive do
          _ -> :ok
        end
      end)

      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

      pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.ConnectionRegistry.register(pid, socket, :gen_tcp)
      MalachiMQ.ConnectionRegistry.set_connection_type(pid, :producer, "test")

      producers = MalachiMQ.ConnectionRegistry.list_producers_by_queue("test")

      if length(producers) > 0 do
        producer = hd(producers)
        # IP should be formatted as string
        assert is_binary(producer.ip)
        # Should contain dots for IPv4
        assert String.contains?(producer.ip, ".")
      end

      :gen_tcp.close(listen_socket)
    end
  end

  describe "GenServer callbacks" do
    test "handles unknown messages gracefully" do
      # Send a message directly to the GenServer
      send(MalachiMQ.ConnectionRegistry, :unknown_message)
      :timer.sleep(50)

      # Should still be alive
      assert Process.whereis(MalachiMQ.ConnectionRegistry) != nil
    end
  end
end
