defmodule MalachiMQ.TCPQueueManagementTest do
  use ExUnit.Case

  @tcp_port Application.compile_env(:malachimq, :tcp_port, 4040)

  setup do
    queue_name = "tcp_queue_mgmt_#{:rand.uniform(1_000_000)}"

    # Connect and authenticate as admin
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @tcp_port, [:binary, packet: :line, active: false])

    auth_msg = Jason.encode!(%{"action" => "auth", "username" => "admin", "password" => "admin123"})
    :gen_tcp.send(socket, auth_msg <> "\n")

    {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
    {:ok, %{"s" => "ok", "token" => _token}} = Jason.decode(String.trim(response))

    on_exit(fn ->
      :gen_tcp.close(socket)
    end)

    {:ok, socket: socket, queue_name: queue_name}
  end

  describe "create_queue action" do
    test "creates queue with at_least_once mode", %{socket: socket, queue_name: queue_name} do
      msg =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => queue_name,
          "delivery_mode" => "at_least_once"
        })

      :gen_tcp.send(socket, msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      assert parsed["config"]["queue_name"] == queue_name
      assert parsed["config"]["delivery_mode"] == "at_least_once"
      assert parsed["config"]["max_retries"] == 3
      assert parsed["config"]["dlq_enabled"] == true
    end

    test "creates queue with at_most_once mode", %{socket: socket, queue_name: queue_name} do
      msg =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => queue_name,
          "delivery_mode" => "at_most_once"
        })

      :gen_tcp.send(socket, msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      assert parsed["config"]["delivery_mode"] == "at_most_once"
    end

    test "creates queue with custom max_retries", %{socket: socket, queue_name: queue_name} do
      msg =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => queue_name,
          "max_retries" => 5
        })

      :gen_tcp.send(socket, msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["config"]["max_retries"] == 5
    end

    test "creates queue with DLQ disabled", %{socket: socket, queue_name: queue_name} do
      msg =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => queue_name,
          "dlq_enabled" => false
        })

      :gen_tcp.send(socket, msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["config"]["dlq_enabled"] == false
    end

    test "returns error for duplicate queue", %{socket: socket, queue_name: queue_name} do
      # Create first time
      msg = Jason.encode!(%{"action" => "create_queue", "queue_name" => queue_name})
      :gen_tcp.send(socket, msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      # Try to create again
      :gen_tcp.send(socket, msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "queue_already_exists"
    end

    test "returns error for invalid delivery mode", %{socket: socket, queue_name: queue_name} do
      msg =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => queue_name,
          "delivery_mode" => "invalid_mode"
        })

      :gen_tcp.send(socket, msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "invalid_delivery_mode"
    end
  end

  describe "get_queue_info action" do
    test "returns queue info", %{socket: socket, queue_name: queue_name} do
      # Create queue first
      create_msg =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => queue_name,
          "delivery_mode" => "at_most_once"
        })

      :gen_tcp.send(socket, create_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      # Get info
      info_msg = Jason.encode!(%{"action" => "get_queue_info", "queue_name" => queue_name})
      :gen_tcp.send(socket, info_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      assert parsed["queue_info"]["queue_name"] == queue_name
      assert parsed["queue_info"]["delivery_mode"] == "at_most_once"
      assert parsed["queue_info"]["implicit"] == false
      assert is_map(parsed["queue_info"]["stats"])
    end

    test "returns info for implicitly created queue", %{socket: socket, queue_name: queue_name} do
      # Publish to create implicit queue
      publish_msg = Jason.encode!(%{"queue_name" => queue_name, "payload" => "test"})
      :gen_tcp.send(socket, publish_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      # Get info
      info_msg = Jason.encode!(%{"action" => "get_queue_info", "queue_name" => queue_name})
      :gen_tcp.send(socket, info_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["queue_info"]["implicit"] == true
      assert parsed["queue_info"]["delivery_mode"] == "at_least_once"
    end
  end

  describe "list_queues action" do
    test "lists all queues", %{socket: socket} do
      # Create a couple of queues
      queue1 = "list_test_1_#{:rand.uniform(1_000_000)}"
      queue2 = "list_test_2_#{:rand.uniform(1_000_000)}"

      create1 = Jason.encode!(%{"action" => "create_queue", "queue_name" => queue1})
      :gen_tcp.send(socket, create1 <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      create2 =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => queue2,
          "delivery_mode" => "at_most_once"
        })

      :gen_tcp.send(socket, create2 <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      # List queues
      list_msg = Jason.encode!(%{"action" => "list_queues"})
      :gen_tcp.send(socket, list_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      assert is_list(parsed["queues"])

      queue_names = Enum.map(parsed["queues"], & &1["queue_name"])
      assert queue1 in queue_names
      assert queue2 in queue_names
    end
  end

  describe "delete_queue action" do
    test "deletes empty queue", %{socket: socket, queue_name: queue_name} do
      # Create queue
      create_msg = Jason.encode!(%{"action" => "create_queue", "queue_name" => queue_name})
      :gen_tcp.send(socket, create_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      # Delete queue
      delete_msg = Jason.encode!(%{"action" => "delete_queue", "queue_name" => queue_name})
      :gen_tcp.send(socket, delete_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      refute MalachiMQ.QueueConfig.exists?(queue_name)
    end

    test "returns error for queue with buffered messages", %{socket: socket, queue_name: queue_name} do
      # Create queue and publish message
      create_msg = Jason.encode!(%{"action" => "create_queue", "queue_name" => queue_name})
      :gen_tcp.send(socket, create_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      publish_msg = Jason.encode!(%{"queue_name" => queue_name, "payload" => "test"})
      :gen_tcp.send(socket, publish_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      # Try to delete
      delete_msg = Jason.encode!(%{"action" => "delete_queue", "queue_name" => queue_name})
      :gen_tcp.send(socket, delete_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "queue_has_buffered_messages"
    end

    test "force deletes queue with buffered messages", %{socket: socket, queue_name: queue_name} do
      # Create queue and publish message
      create_msg = Jason.encode!(%{"action" => "create_queue", "queue_name" => queue_name})
      :gen_tcp.send(socket, create_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      publish_msg = Jason.encode!(%{"queue_name" => queue_name, "payload" => "test"})
      :gen_tcp.send(socket, publish_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      # Force delete
      delete_msg =
        Jason.encode!(%{
          "action" => "delete_queue",
          "queue_name" => queue_name,
          "force" => true
        })

      :gen_tcp.send(socket, delete_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      refute MalachiMQ.QueueConfig.exists?(queue_name)
    end

    test "returns error for non-existent queue", %{socket: socket} do
      delete_msg =
        Jason.encode!(%{
          "action" => "delete_queue",
          "queue_name" => "non_existent_#{:rand.uniform(1_000_000)}"
        })

      :gen_tcp.send(socket, delete_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "queue_not_found"
    end
  end

  describe "permission checks" do
    test "non-admin cannot create queue" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @tcp_port, [:binary, packet: :line, active: false])

      auth_msg = Jason.encode!(%{"action" => "auth", "username" => "producer", "password" => "producer123"})
      :gen_tcp.send(socket, auth_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      create_msg =
        Jason.encode!(%{
          "action" => "create_queue",
          "queue_name" => "test_#{:rand.uniform(1_000_000)}"
        })

      :gen_tcp.send(socket, create_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "permission_denied"

      :gen_tcp.close(socket)
    end

    test "non-admin cannot delete queue" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @tcp_port, [:binary, packet: :line, active: false])

      auth_msg = Jason.encode!(%{"action" => "auth", "username" => "producer", "password" => "producer123"})
      :gen_tcp.send(socket, auth_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      delete_msg =
        Jason.encode!(%{
          "action" => "delete_queue",
          "queue_name" => "test_#{:rand.uniform(1_000_000)}"
        })

      :gen_tcp.send(socket, delete_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "err"
      assert parsed["reason"] == "permission_denied"

      :gen_tcp.close(socket)
    end

    test "producer can get queue info" do
      {:ok, socket} = :gen_tcp.connect(~c"localhost", @tcp_port, [:binary, packet: :line, active: false])

      auth_msg = Jason.encode!(%{"action" => "auth", "username" => "producer", "password" => "producer123"})
      :gen_tcp.send(socket, auth_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      queue_name = "producer_info_test_#{:rand.uniform(1_000_000)}"

      # Publish to create implicit queue
      publish_msg = Jason.encode!(%{"queue_name" => queue_name, "payload" => "test"})
      :gen_tcp.send(socket, publish_msg <> "\n")
      {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

      info_msg = Jason.encode!(%{"action" => "get_queue_info", "queue_name" => queue_name})
      :gen_tcp.send(socket, info_msg <> "\n")
      {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
      {:ok, parsed} = Jason.decode(String.trim(response))

      assert parsed["s"] == "ok"
      assert parsed["queue_info"]["queue_name"] == queue_name

      :gen_tcp.close(socket)
    end
  end
end
