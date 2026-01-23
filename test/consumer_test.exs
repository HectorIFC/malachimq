defmodule MalachiMQ.ConsumerTest do
  use ExUnit.Case, async: true

  setup do
    queue_name = "consumer_test_#{:rand.uniform(100_000)}"
    {:ok, queue_name: queue_name}
  end

  describe "start_link/1" do
    test "starts consumer with callback", %{queue_name: queue_name} do
      callback = fn _msg -> :ok end
      assert {:ok, pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      assert Process.alive?(pid)
    end

    test "consumer subscribes to queue on init", %{queue_name: queue_name} do
      callback = fn _msg -> :ok end
      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})

      :timer.sleep(50)
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.consumers == 1
    end
  end

  describe "message processing" do
    test "processes message with callback", %{queue_name: queue_name} do
      test_pid = self()

      callback = fn msg ->
        send(test_pid, {:processed, msg.payload})
        :ok
      end

      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      MalachiMQ.Queue.enqueue(queue_name, "test payload")

      assert_receive {:processed, "test payload"}, 1000
    end

    test "processes multiple messages", %{queue_name: queue_name} do
      test_pid = self()

      callback = fn msg ->
        send(test_pid, {:processed, msg.payload})
        :ok
      end

      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      for i <- 1..5 do
        MalachiMQ.Queue.enqueue(queue_name, "msg_#{i}")
      end

      for _i <- 1..5 do
        assert_receive {:processed, _payload}, 1000
      end
    end

    test "acknowledges successful processing", %{queue_name: queue_name} do
      callback = fn _msg -> :ok end

      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      MalachiMQ.Queue.enqueue(queue_name, "test")
      :timer.sleep(100)

      stats = MalachiMQ.AckManager.stats()
      pending = Map.get(stats, queue_name, %{count: 0})
      assert pending.count == 0
    end

    test "nacks on error result", %{queue_name: queue_name} do
      test_pid = self()

      callback = fn _msg ->
        send(test_pid, :called)
        :error
      end

      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      MalachiMQ.Queue.enqueue(queue_name, "test")

      assert_receive :called, 1000
      :timer.sleep(100)
    end

    test "nacks on {:error, reason} result", %{queue_name: queue_name} do
      test_pid = self()

      callback = fn _msg ->
        send(test_pid, :called)
        {:error, "failed"}
      end

      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      MalachiMQ.Queue.enqueue(queue_name, "test")

      assert_receive :called, 1000
      :timer.sleep(100)
    end

    test "handles callback exceptions", %{queue_name: queue_name} do
      callback = fn _msg ->
        raise "test error"
      end

      {:ok, pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      MalachiMQ.Queue.enqueue(queue_name, "test")
      :timer.sleep(200)

      assert Process.alive?(pid)
    end
  end

  describe "hibernation" do
    test "consumer hibernates after initialization", %{queue_name: queue_name} do
      callback = fn _msg -> :ok end
      {:ok, pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})

      :timer.sleep(50)
      {:current_function, {_mod, func, _arity}} = Process.info(pid, :current_function)
      assert func in [:hibernate, :loop_hibernate]
    end
  end

  describe "garbage collection" do
    test "consumer performs GC after interval", %{queue_name: queue_name} do
      Application.put_env(:malachimq, :gc_interval_ms, 100)

      callback = fn _msg -> :ok end
      {:ok, pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      # Send messages to trigger GC interval
      for _ <- 1..5 do
        MalachiMQ.Queue.enqueue(queue_name, "test")
        :timer.sleep(50)
      end

      assert Process.alive?(pid)

      Application.delete_env(:malachimq, :gc_interval_ms)
    end
  end

  describe "message queue configuration" do
    test "consumer uses off-heap message queue", %{queue_name: queue_name} do
      callback = fn _msg -> :ok end
      {:ok, pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})

      :timer.sleep(50)
      {:message_queue_data, queue_type} = Process.info(pid, :message_queue_data)
      assert queue_type == :off_heap
    end
  end
end
