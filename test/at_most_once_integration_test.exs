defmodule MalachiMQ.AtMostOnceIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  setup do
    queue_name = "at_most_once_integration_#{:rand.uniform(1_000_000)}"
    {:ok, queue_name: queue_name}
  end

  describe "at_most_once delivery mode end-to-end" do
    test "messages are delivered without ack tracking", %{queue_name: queue_name} do
      # Create at_most_once queue
      {:ok, config} = MalachiMQ.QueueConfig.create_queue(queue_name, delivery_mode: :at_most_once)
      assert config.delivery_mode == :at_most_once

      # Track received messages
      test_pid = self()
      received_count = :atomics.new(1, signed: false)

      # Create consumer that doesn't ack
      consumer_callback = fn msg ->
        :atomics.add(received_count, 1, 1)
        send(test_pid, {:received, msg.payload})
        :ok
      end

      # Start consumer
      {:ok, _consumer} = MalachiMQ.Consumer.start_link({queue_name, consumer_callback, []})
      :timer.sleep(50)

      # Publish messages
      messages = for i <- 1..10, do: "message_#{i}"

      Enum.each(messages, fn payload ->
        MalachiMQ.Queue.enqueue(queue_name, payload)
      end)

      # Verify all messages received
      received_messages =
        for _i <- 1..10 do
          assert_receive {:received, msg}, 1000
          msg
        end

      # Verify all expected messages were received
      assert Enum.sort(received_messages) == Enum.sort(messages)

      # Verify no messages are pending in AckManager (at_most_once doesn't track)
      pending = MalachiMQ.AckManager.pending_count(queue_name)
      assert pending == 0

      # Verify metrics
      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.delivery_mode == :at_most_once
      assert metrics.enqueued == 10
      assert metrics.processed == 10
      # At-most-once queues don't track acks
      assert metrics.acked == 0
      assert metrics.nacked == 0
    end

    test "failed messages are silently dropped in at_most_once mode", %{queue_name: queue_name} do
      # Create at_most_once queue
      {:ok, _config} = MalachiMQ.QueueConfig.create_queue(queue_name, delivery_mode: :at_most_once)

      test_pid = self()

      # Consumer that fails for every other message
      consumer_callback = fn msg ->
        payload = msg.payload
        send(test_pid, {:processing, payload})

        if String.ends_with?(payload, "_fail") do
          raise "Intentional failure"
        else
          :ok
        end
      end

      # Start consumer
      {:ok, _consumer} = MalachiMQ.Consumer.start_link({queue_name, consumer_callback, []})
      :timer.sleep(50)

      # Publish mix of successful and failing messages
      MalachiMQ.Queue.enqueue(queue_name, "msg_1_success")
      MalachiMQ.Queue.enqueue(queue_name, "msg_2_fail")
      MalachiMQ.Queue.enqueue(queue_name, "msg_3_success")
      MalachiMQ.Queue.enqueue(queue_name, "msg_4_fail")

      # All messages should be processed
      assert_receive {:processing, "msg_1_success"}, 1000
      assert_receive {:processing, "msg_2_fail"}, 1000
      assert_receive {:processing, "msg_3_success"}, 1000
      assert_receive {:processing, "msg_4_fail"}, 1000

      :timer.sleep(100)

      # Verify metrics: 2 errors, 0 retries (at_most_once doesn't retry)
      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.errors == 2
      assert metrics.retried == 0
      assert metrics.dead_lettered == 0
      assert metrics.nacked == 0

      # Verify no pending messages (failed messages were dropped)
      assert metrics.pending_ack == 0
    end

    test "at_least_once mode retries failed messages for comparison", %{queue_name: queue_name} do
      # Create at_least_once queue (default)
      {:ok, config} = MalachiMQ.QueueConfig.create_queue(queue_name, delivery_mode: :at_least_once)
      assert config.delivery_mode == :at_least_once

      test_pid = self()
      attempt_count = :atomics.new(1, signed: false)

      # Consumer that fails on first attempt, succeeds on retry
      consumer_callback = fn msg ->
        attempts = :atomics.add_get(attempt_count, 1, 1)
        send(test_pid, {:attempt, attempts, msg.payload})

        if attempts == 1 do
          {:error, :first_attempt_fails}
        else
          :ok
        end
      end

      # Start consumer
      {:ok, _consumer} = MalachiMQ.Consumer.start_link({queue_name, consumer_callback, []})
      :timer.sleep(50)

      # Publish one message
      MalachiMQ.Queue.enqueue(queue_name, "retry_test")

      # Should see first attempt
      assert_receive {:attempt, 1, "retry_test"}, 1000

      # Message should be nacked and requeued
      :timer.sleep(200)

      # Should see second attempt (retry)
      assert_receive {:attempt, 2, "retry_test"}, 2000

      # Verify metrics show retry
      :timer.sleep(100)
      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.delivery_mode == :at_least_once
      # Original + requeue
      assert metrics.enqueued >= 1
      assert metrics.nacked >= 1
      assert metrics.acked >= 1
    end

    test "queue info shows correct delivery mode", %{queue_name: queue_name} do
      # Create at_most_once queue
      {:ok, _} =
        MalachiMQ.QueueConfig.create_queue(queue_name,
          delivery_mode: :at_most_once,
          max_retries: 5,
          dlq_enabled: false
        )

      # Get config
      config = MalachiMQ.QueueConfig.get_config(queue_name)

      assert config.queue_name == queue_name
      assert config.delivery_mode == :at_most_once
      assert config.max_retries == 5
      assert config.dlq_enabled == false
      # Explicitly created queues don't have implicit flag
      refute Map.has_key?(config, :implicit)
    end

    test "implicit queue creation uses default delivery mode", %{queue_name: queue_name} do
      # Don't create queue explicitly, just publish
      MalachiMQ.Queue.enqueue(queue_name, "test")

      # Should create implicit queue
      config = MalachiMQ.QueueConfig.get_config(queue_name)

      assert config.queue_name == queue_name
      # Default
      assert config.delivery_mode == :at_least_once
      assert config.implicit == true
    end
  end

  describe "queue lifecycle" do
    test "cannot delete queue with active consumers", %{queue_name: queue_name} do
      {:ok, _} = MalachiMQ.QueueConfig.create_queue(queue_name)

      # Create consumer
      consumer_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)
      :timer.sleep(50)

      # Should fail to delete
      assert {:error, :queue_has_active_consumers} = MalachiMQ.QueueConfig.delete_queue(queue_name)

      # Force delete should work
      assert :ok = MalachiMQ.QueueConfig.delete_queue(queue_name, force: true)

      send(consumer_pid, :stop)
    end

    test "cannot delete queue with buffered messages", %{queue_name: queue_name} do
      {:ok, _} = MalachiMQ.QueueConfig.create_queue(queue_name)

      # Enqueue messages
      MalachiMQ.Queue.enqueue(queue_name, "msg1")
      MalachiMQ.Queue.enqueue(queue_name, "msg2")
      :timer.sleep(50)

      # Should fail to delete
      assert {:error, :queue_has_buffered_messages} = MalachiMQ.QueueConfig.delete_queue(queue_name)

      # Force delete should work
      assert :ok = MalachiMQ.QueueConfig.delete_queue(queue_name, force: true)
    end

    test "can delete empty queue", %{queue_name: queue_name} do
      {:ok, _} = MalachiMQ.QueueConfig.create_queue(queue_name)

      # Should successfully delete
      assert :ok = MalachiMQ.QueueConfig.delete_queue(queue_name)

      # Should no longer exist
      refute MalachiMQ.QueueConfig.exists?(queue_name)
    end
  end
end
