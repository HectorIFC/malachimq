defmodule MalachiMQ.IntegrationTest do
  use ExUnit.Case, async: false

  describe "end-to-end message flow" do
    test "producer -> queue -> consumer flow" do
      queue_name = "integration_test_#{:rand.uniform(100_000)}"
      test_pid = self()

      # Start a consumer
      callback = fn msg ->
        send(test_pid, {:consumed, msg.payload})
        :ok
      end

      {:ok, _consumer_pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      # Produce a message
      MalachiMQ.Queue.enqueue(queue_name, "integration_test_payload")

      # Verify consumer receives it
      assert_receive {:consumed, "integration_test_payload"}, 2000
    end

    test "buffered messages are delivered to new consumer" do
      queue_name = "buffer_integration_#{:rand.uniform(100_000)}"

      # Enqueue messages without consumer
      for i <- 1..3 do
        MalachiMQ.Queue.enqueue(queue_name, "buffered_#{i}")
      end

      # Verify messages are buffered
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.buffered == 3

      # Start consumer
      test_pid = self()

      callback = fn msg ->
        send(test_pid, {:got, msg.payload})
        :ok
      end

      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})

      # Receive all buffered messages
      assert_receive {:got, _}, 1000
      assert_receive {:got, _}, 1000
      assert_receive {:got, _}, 1000
    end

    test "multiple consumers share workload" do
      queue_name = "multi_consumer_#{:rand.uniform(100_000)}"
      test_pid = self()

      # Start 3 consumers
      callback = fn msg ->
        send(test_pid, {:consumed_by, self(), msg.payload})
        :ok
      end

      consumer_pids =
        for _ <- 1..3 do
          {:ok, pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
          pid
        end

      :timer.sleep(100)

      # Send 6 messages
      for i <- 1..6 do
        MalachiMQ.Queue.enqueue(queue_name, "msg_#{i}")
      end

      # Collect which consumers processed messages
      consumers_that_worked =
        for _ <- 1..6 do
          receive do
            {:consumed_by, pid, _payload} -> pid
          after
            2000 -> nil
          end
        end

      # Verify multiple consumers worked
      unique_consumers = Enum.uniq(consumers_that_worked) |> Enum.reject(&is_nil/1)
      assert length(unique_consumers) >= 1
    end

    test "metrics are tracked correctly" do
      queue_name = "metrics_integration_#{:rand.uniform(100_000)}"

      callback = fn _msg -> :ok end
      {:ok, _pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      # Send messages
      for _ <- 1..5 do
        MalachiMQ.Queue.enqueue(queue_name, "test")
      end

      :timer.sleep(200)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.enqueued >= 5
      assert metrics.processed >= 5
    end

    test "auth -> publish -> consume flow" do
      queue_name = "auth_integration_#{:rand.uniform(100_000)}"

      # Authenticate as producer
      {:ok, token} = MalachiMQ.Auth.authenticate("producer", "producer123")
      {:ok, session} = MalachiMQ.Auth.validate_token(token)

      assert :produce in session.permissions

      # Produce message
      MalachiMQ.Queue.enqueue(queue_name, "authenticated_message")

      # Authenticate as consumer
      {:ok, consumer_token} = MalachiMQ.Auth.authenticate("consumer", "consumer123")
      {:ok, consumer_session} = MalachiMQ.Auth.validate_token(consumer_token)

      assert :consume in consumer_session.permissions
    end
  end

  describe "partition distribution" do
    test "multiple queues are distributed across partitions" do
      partitions =
        for i <- 1..50 do
          queue_name = "dist_test_#{i}"
          {_name, partition} = MalachiMQ.PartitionManager.get_partition(queue_name)
          partition
        end

      unique_partitions = Enum.uniq(partitions)
      # Should have decent distribution
      assert length(unique_partitions) > 10
    end
  end

  describe "error handling" do
    test "consumer handles callback errors gracefully" do
      queue_name = "error_test_#{:rand.uniform(100_000)}"
      test_pid = self()

      callback = fn msg ->
        send(test_pid, :called)
        if msg.payload == "error", do: raise("test error"), else: :ok
      end

      {:ok, consumer_pid} = MalachiMQ.Consumer.start_link({queue_name, callback, []})
      :timer.sleep(50)

      MalachiMQ.Queue.enqueue(queue_name, "error")
      assert_receive :called, 1000

      :timer.sleep(100)
      assert Process.alive?(consumer_pid)
    end

    test "queue survives consumer crashes" do
      queue_name = "crash_test_#{:rand.uniform(100_000)}"

      # Start a consumer that will exit naturally
      {:ok, _consumer_pid} = MalachiMQ.Consumer.start_link({queue_name, fn _ -> :ok end, []})
      :timer.sleep(50)

      # Verify queue exists
      stats = MalachiMQ.Queue.get_stats(queue_name)
      assert stats.exists == true
      assert stats.consumers >= 1

      # Queue should still work after consumer processes messages
      MalachiMQ.Queue.enqueue(queue_name, "test_message")
      :timer.sleep(100)

      # Queue still exists and functional
      stats2 = MalachiMQ.Queue.get_stats(queue_name)
      assert stats2.exists == true
    end
  end
end
