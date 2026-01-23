defmodule MalachiMQ.TCPQueueManagementTest do
  use ExUnit.Case
  alias MalachiMQ.Test.TCPHelper

  @tcp_port Application.compile_env(:malachimq, :tcp_port, 4040)

  setup do
    queue_name = "tcp_queue_mgmt_#{:rand.uniform(1_000_000)}"

    # Connect and authenticate as admin
    {:ok, socket} = TCPHelper.connect(port: @tcp_port)

    case TCPHelper.authenticate(socket, "admin", "admin123") do
      {:ok, _token} ->
        on_exit(fn ->
          :gen_tcp.close(socket)
        end)

        {:ok, socket: socket, queue_name: queue_name}

      {:error, reason} ->
        :gen_tcp.close(socket)
        raise "Authentication failed: #{inspect(reason)}"
    end
  end

  # Helper to send and receive in packet: 0 mode
  defp send_and_recv(socket, msg) do
    TCPHelper.send_line(socket, Jason.encode!(msg))

    case TCPHelper.recv_line(socket) do
      {:ok, response} ->
        Jason.decode(String.trim(response))

      error ->
        error
    end
  end

  describe "create_queue action" do
    test "creates queue with at_least_once mode", %{socket: socket, queue_name: queue_name} do
      msg = %{
        "action" => "create_queue",
        "queue_name" => queue_name,
        "delivery_mode" => "at_least_once"
      }

      {:ok, parsed} = send_and_recv(socket, msg)

      assert parsed["s"] == "ok"
      assert parsed["config"]["queue_name"] == queue_name
      assert parsed["config"]["delivery_mode"] == "at_least_once"
      assert parsed["config"]["max_retries"] == 3
      assert parsed["config"]["dlq_enabled"] == true
    end

    test "creates queue with at_most_once mode", %{socket: socket, queue_name: queue_name} do
      msg = %{
        "action" => "create_queue",
        "queue_name" => queue_name,
        "delivery_mode" => "at_most_once"
      }

      {:ok, parsed} = send_and_recv(socket, msg)

      assert parsed["s"] == "ok"
      assert parsed["config"]["delivery_mode"] == "at_most_once"
    end

    test "creates queue with custom max_retries", %{socket: socket, queue_name: queue_name} do
      msg = %{
        "action" => "create_queue",
        "queue_name" => queue_name,
        "max_retries" => 5
      }

      {:ok, parsed} = send_and_recv(socket, msg)

      assert parsed["config"]["max_retries"] == 5
    end

    test "creates queue with DLQ disabled", %{socket: socket, queue_name: queue_name} do
      msg = %{
        "action" => "create_queue",
        "queue_name" => queue_name,
        "dlq_enabled" => false
      }

      {:ok, parsed} = send_and_recv(socket, msg)

      assert parsed["config"]["dlq_enabled"] == false
    end

    test "returns error for duplicate queue", %{socket: socket, queue_name: queue_name} do
      # Create first time
      msg = %{"action" => "create_queue", "queue_name" => queue_name}
      {:ok, _} = send_and_recv(socket, msg)

      # Try to create again
      {:ok, parsed} = send_and_recv(socket, msg)

      assert parsed["s"] == "err"
      assert parsed["reason"] == "queue_already_exists"
    end

    test "returns error for invalid delivery mode", %{socket: socket, queue_name: queue_name} do
      msg = %{
        "action" => "create_queue",
        "queue_name" => queue_name,
        "delivery_mode" => "invalid_mode"
      }

      {:ok, parsed} = send_and_recv(socket, msg)

      assert parsed["s"] == "err"
      assert parsed["reason"] == "invalid_delivery_mode"
    end
  end

  describe "get_queue_info action" do
    test "returns queue info", %{socket: socket, queue_name: queue_name} do
      # Create queue first
      create_msg = %{
        "action" => "create_queue",
        "queue_name" => queue_name,
        "delivery_mode" => "at_most_once"
      }

      {:ok, _} = send_and_recv(socket, create_msg)

      # Get info
      info_msg = %{"action" => "get_queue_info", "queue_name" => queue_name}
      {:ok, parsed} = send_and_recv(socket, info_msg)

      assert parsed["s"] == "ok"
      assert parsed["queue_info"]["queue_name"] == queue_name
      assert parsed["queue_info"]["delivery_mode"] == "at_most_once"
      assert parsed["queue_info"]["implicit"] == false
      assert is_map(parsed["queue_info"]["stats"])
    end

    test "returns info for implicitly created queue", %{socket: socket, queue_name: queue_name} do
      # Publish to create implicit queue
      publish_msg = %{"queue_name" => queue_name, "payload" => "test"}
      {:ok, _} = send_and_recv(socket, publish_msg)

      # Get info
      info_msg = %{"action" => "get_queue_info", "queue_name" => queue_name}
      {:ok, parsed} = send_and_recv(socket, info_msg)

      assert parsed["queue_info"]["implicit"] == true
      assert parsed["queue_info"]["delivery_mode"] == "at_least_once"
    end
  end

  describe "list_queues action" do
    test "lists all queues", %{socket: socket} do
      # Create a couple of queues
      queue1 = "list_test_1_#{:rand.uniform(1_000_000)}"
      queue2 = "list_test_2_#{:rand.uniform(1_000_000)}"

      create1 = %{"action" => "create_queue", "queue_name" => queue1}
      {:ok, _} = send_and_recv(socket, create1)

      create2 = %{
        "action" => "create_queue",
        "queue_name" => queue2,
        "delivery_mode" => "at_most_once"
      }

      {:ok, _} = send_and_recv(socket, create2)

      # List queues
      list_msg = %{"action" => "list_queues"}
      {:ok, parsed} = send_and_recv(socket, list_msg)

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
      create_msg = %{"action" => "create_queue", "queue_name" => queue_name}
      {:ok, _} = send_and_recv(socket, create_msg)

      # Delete queue
      delete_msg = %{"action" => "delete_queue", "queue_name" => queue_name}
      {:ok, parsed} = send_and_recv(socket, delete_msg)

      assert parsed["s"] == "ok"
      refute MalachiMQ.QueueConfig.exists?(queue_name)
    end

    test "returns error for queue with buffered messages", %{socket: socket, queue_name: queue_name} do
      # Create queue and publish message
      create_msg = %{"action" => "create_queue", "queue_name" => queue_name}
      {:ok, _} = send_and_recv(socket, create_msg)

      publish_msg = %{"queue_name" => queue_name, "payload" => "test"}
      {:ok, _} = send_and_recv(socket, publish_msg)

      # Try to delete
      delete_msg = %{"action" => "delete_queue", "queue_name" => queue_name}
      {:ok, parsed} = send_and_recv(socket, delete_msg)

      assert parsed["s"] == "err"
      assert parsed["reason"] == "queue_has_buffered_messages"
    end

    test "force deletes queue with buffered messages", %{socket: socket, queue_name: queue_name} do
      # Create queue and publish message
      create_msg = %{"action" => "create_queue", "queue_name" => queue_name}
      {:ok, _} = send_and_recv(socket, create_msg)

      publish_msg = %{"queue_name" => queue_name, "payload" => "test"}
      {:ok, _} = send_and_recv(socket, publish_msg)

      # Force delete
      delete_msg = %{
        "action" => "delete_queue",
        "queue_name" => queue_name,
        "force" => true
      }

      {:ok, parsed} = send_and_recv(socket, delete_msg)

      assert parsed["s"] == "ok"
      refute MalachiMQ.QueueConfig.exists?(queue_name)
    end

    test "returns error for non-existent queue", %{socket: socket} do
      delete_msg = %{
        "action" => "delete_queue",
        "queue_name" => "non_existent_#{:rand.uniform(1_000_000)}"
      }

      {:ok, parsed} = send_and_recv(socket, delete_msg)

      assert parsed["s"] == "err"
      assert parsed["reason"] == "queue_not_found"
    end
  end

  describe "permission checks" do
    test "non-admin cannot create queue" do
      {:ok, socket} = TCPHelper.connect(port: @tcp_port)

      case TCPHelper.authenticate(socket, "producer", "producer123") do
        {:ok, _token} ->
          create_msg = %{
            "action" => "create_queue",
            "queue_name" => "test_#{:rand.uniform(1_000_000)}"
          }

          {:ok, parsed} = send_and_recv(socket, create_msg)

          assert parsed["s"] == "err"
          assert parsed["reason"] == "permission_denied"

        {:error, _} ->
          :ok
      end

      :gen_tcp.close(socket)
    end

    test "non-admin cannot delete queue" do
      {:ok, socket} = TCPHelper.connect(port: @tcp_port)

      case TCPHelper.authenticate(socket, "producer", "producer123") do
        {:ok, _token} ->
          delete_msg = %{
            "action" => "delete_queue",
            "queue_name" => "test_#{:rand.uniform(1_000_000)}"
          }

          {:ok, parsed} = send_and_recv(socket, delete_msg)

          assert parsed["s"] == "err"
          assert parsed["reason"] == "permission_denied"

        {:error, _} ->
          :ok
      end

      :gen_tcp.close(socket)
    end

    test "producer can get queue info" do
      {:ok, socket} = TCPHelper.connect(port: @tcp_port)

      case TCPHelper.authenticate(socket, "producer", "producer123") do
        {:ok, _token} ->
          queue_name = "producer_info_test_#{:rand.uniform(1_000_000)}"

          # Publish to create implicit queue
          publish_msg = %{"queue_name" => queue_name, "payload" => "test"}
          {:ok, _} = send_and_recv(socket, publish_msg)

          info_msg = %{"action" => "get_queue_info", "queue_name" => queue_name}
          {:ok, parsed} = send_and_recv(socket, info_msg)

          assert parsed["s"] == "ok"
          assert parsed["queue_info"]["queue_name"] == queue_name

        {:error, _} ->
          :ok
      end

      :gen_tcp.close(socket)
    end
  end
end
