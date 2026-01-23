defmodule MalachiMQ.QueueTest do
  use ExUnit.Case, async: true

  setup do
    queue_name = "test_queue_#{:rand.uniform(100_000)}"
    {:ok, queue_name: queue_name}
  end

  describe "enqueue/3" do
    test "enqueues a message successfully", %{queue_name: queue_name} do
      assert :ok = MalachiMQ.Queue.enqueue(queue_name, "test payload")
    end

    test "enqueues message with headers", %{queue_name: queue_name} do
      headers = %{"priority" => 1, "type" => "test"}
      assert :ok = MalachiMQ.Queue.enqueue(queue_name, "test payload", headers)
    end

    test "enqueues multiple messages", %{queue_name: queue_name} do
      for i <- 1..10 do
        assert :ok = MalachiMQ.Queue.enqueue(queue_name, "payload_#{i}")
      end
    end
  end

  describe "subscribe/2" do
    test "consumer can subscribe to queue", %{queue_name: queue_name} do
      consumer_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      assert :ok = MalachiMQ.Queue.subscribe(queue_name, consumer_pid)
    end

    test "multiple consumers can subscribe", %{queue_name: queue_name} do
      consumers =
        for _ <- 1..5 do
          spawn(fn ->
            receive do
              _ -> :ok
            end
          end)
        end

      Enum.each(consumers, fn pid ->
        assert :ok = MalachiMQ.Queue.subscribe(queue_name, pid)
      end)
    end

    test "subscribed consumer receives message", %{queue_name: queue_name} do
      test_pid = self()

      consumer_pid =
        spawn(fn ->
          receive do
            {:queue_message, msg} -> send(test_pid, {:received, msg})
          after
            1000 -> send(test_pid, :timeout)
          end
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)
      MalachiMQ.Queue.enqueue(queue_name, "test payload")

      assert_receive {:received, %{payload: "test payload"}}, 2000
    end
  end

  describe "get_stats/1" do
    test "returns stats for non-existent queue", %{queue_name: queue_name} do
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.exists == false
      assert stats.consumers == 0
      assert stats.producers == 0
    end

    test "returns stats for existing queue", %{queue_name: queue_name} do
      MalachiMQ.Queue.enqueue(queue_name, "test")
      stats = MalachiMQ.Queue.get_stats(queue_name)

      assert stats.exists == true
      assert is_integer(stats.partition)
      assert is_integer(stats.buffered)
    end

    test "tracks consumer count", %{queue_name: queue_name} do
      consumer_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)

      :timer.sleep(50)
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.consumers == 1
    end

    test "tracks buffered messages", %{queue_name: queue_name} do
      MalachiMQ.Queue.enqueue(queue_name, "msg1")
      MalachiMQ.Queue.enqueue(queue_name, "msg2")

      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.buffered == 2
    end
  end

  describe "kill_all_consumers/1" do
    test "returns 0 for non-existent queue", %{queue_name: queue_name} do
      assert {:ok, 0} = MalachiMQ.Queue.kill_all_consumers(queue_name)
    end

    test "kills all consumers", %{queue_name: queue_name} do
      consumers =
        for _ <- 1..3 do
          spawn(fn ->
            Process.flag(:trap_exit, true)

            receive do
              _ -> :ok
            end
          end)
        end

      Enum.each(consumers, &MalachiMQ.Queue.subscribe(queue_name, &1))
      :timer.sleep(50)

      assert {:ok, 3} = MalachiMQ.Queue.kill_all_consumers(queue_name)

      :timer.sleep(50)
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.consumers == 0
    end
  end

  describe "list_consumers/1" do
    test "returns empty list for non-existent queue", %{queue_name: queue_name} do
      assert [] = MalachiMQ.Queue.list_consumers(queue_name)
    end

    test "lists all consumers", %{queue_name: queue_name} do
      consumer_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)

      :timer.sleep(50)
      consumers = MalachiMQ.Queue.list_consumers(queue_name)

      assert length(consumers) == 1
      assert hd(consumers).pid == consumer_pid
      assert hd(consumers).alive == true
      assert is_integer(hd(consumers).registered_at)
    end
  end

  describe "kill_consumer/2" do
    test "returns error for non-existent queue", %{queue_name: queue_name} do
      assert {:error, :queue_not_found} = MalachiMQ.Queue.kill_consumer(queue_name, self())
    end

    test "kills specific consumer", %{queue_name: queue_name} do
      consumer_pid =
        spawn(fn ->
          Process.flag(:trap_exit, true)

          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)
      :timer.sleep(50)

      assert :ok = MalachiMQ.Queue.kill_consumer(queue_name, consumer_pid)

      :timer.sleep(50)
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.consumers == 0
    end

    test "returns error for non-existent consumer", %{queue_name: queue_name} do
      MalachiMQ.Queue.enqueue(queue_name, "test")
      fake_pid = spawn(fn -> :ok end)
      :timer.sleep(50)

      assert {:error, :not_found} = MalachiMQ.Queue.kill_consumer(queue_name, fake_pid)
    end
  end

  describe "message buffering" do
    test "buffers messages when no consumers", %{queue_name: queue_name} do
      MalachiMQ.Queue.enqueue(queue_name, "buffered1")
      MalachiMQ.Queue.enqueue(queue_name, "buffered2")

      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.buffered == 2
    end

    test "flushes buffer to new consumer", %{queue_name: queue_name} do
      MalachiMQ.Queue.enqueue(queue_name, "msg1")
      MalachiMQ.Queue.enqueue(queue_name, "msg2")

      test_pid = self()

      consumer_pid =
        spawn(fn ->
          receive_all = fn receive_all ->
            receive do
              {:queue_message, msg} ->
                send(test_pid, {:got, msg.payload})
                receive_all.(receive_all)
            after
              200 -> :done
            end
          end

          receive_all.(receive_all)
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)

      assert_receive {:got, payload1}, 1000
      assert_receive {:got, payload2}, 1000
      assert payload1 in ["msg1", "msg2"]
      assert payload2 in ["msg1", "msg2"]
    end
  end

  describe "process monitoring" do
    test "removes dead consumer from queue", %{queue_name: queue_name} do
      consumer_pid = spawn(fn -> :ok end)
      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)

      :timer.sleep(100)
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.consumers == 0
    end

    test "removes dead producer from tracking", %{queue_name: queue_name} do
      producer_task =
        Task.async(fn ->
          MalachiMQ.Queue.enqueue(queue_name, "test")
        end)

      Task.await(producer_task)
      :timer.sleep(100)

      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.producers == 0
    end
  end
end
