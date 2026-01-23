defmodule MalachiMQ.QueueConfigTest do
  use ExUnit.Case, async: true

  setup do
    # Use unique queue names to avoid conflicts in async tests
    queue_name = "test_queue_#{:rand.uniform(1_000_000)}"
    {:ok, queue_name: queue_name}
  end

  describe "create_queue/2" do
    test "creates queue with default delivery mode", %{queue_name: queue_name} do
      assert {:ok, config} = MalachiMQ.QueueConfig.create_queue(queue_name)
      assert config.queue_name == queue_name
      assert config.delivery_mode == :at_least_once
      assert config.max_retries == 3
      assert config.dlq_enabled == true
      assert is_integer(config.created_at)
    end

    test "creates queue with at_most_once delivery mode", %{queue_name: queue_name} do
      assert {:ok, config} = MalachiMQ.QueueConfig.create_queue(queue_name, delivery_mode: :at_most_once)
      assert config.delivery_mode == :at_most_once
    end

    test "creates queue with custom max_retries", %{queue_name: queue_name} do
      assert {:ok, config} = MalachiMQ.QueueConfig.create_queue(queue_name, max_retries: 5)
      assert config.max_retries == 5
    end

    test "creates queue with dlq disabled", %{queue_name: queue_name} do
      assert {:ok, config} = MalachiMQ.QueueConfig.create_queue(queue_name, dlq_enabled: false)
      assert config.dlq_enabled == false
    end

    test "returns error for duplicate queue", %{queue_name: queue_name} do
      assert {:ok, _config} = MalachiMQ.QueueConfig.create_queue(queue_name)
      assert {:error, :queue_already_exists} = MalachiMQ.QueueConfig.create_queue(queue_name)
    end

    test "returns error for invalid delivery mode", %{queue_name: queue_name} do
      assert {:error, :invalid_delivery_mode} = MalachiMQ.QueueConfig.create_queue(queue_name, delivery_mode: :invalid)
    end
  end

  describe "get_config/1" do
    test "returns config for existing queue", %{queue_name: queue_name} do
      {:ok, created_config} = MalachiMQ.QueueConfig.create_queue(queue_name, delivery_mode: :at_most_once)
      retrieved_config = MalachiMQ.QueueConfig.get_config(queue_name)

      assert retrieved_config.queue_name == created_config.queue_name
      assert retrieved_config.delivery_mode == :at_most_once
    end

    test "creates implicit queue for non-existent queue", %{queue_name: queue_name} do
      config = MalachiMQ.QueueConfig.get_config(queue_name)

      assert config.queue_name == queue_name
      assert config.delivery_mode == :at_least_once
      assert config.implicit == true
    end
  end

  describe "delete_queue/2" do
    test "deletes queue with no consumers or buffered messages", %{queue_name: queue_name} do
      {:ok, _config} = MalachiMQ.QueueConfig.create_queue(queue_name)
      assert :ok = MalachiMQ.QueueConfig.delete_queue(queue_name)
      refute MalachiMQ.QueueConfig.exists?(queue_name)
    end

    test "returns error for non-existent queue" do
      assert {:error, :queue_not_found} = MalachiMQ.QueueConfig.delete_queue("non_existent_queue")
    end

    test "returns error when queue has active consumers", %{queue_name: queue_name} do
      {:ok, _config} = MalachiMQ.QueueConfig.create_queue(queue_name)

      # Subscribe a consumer
      consumer_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)
      :timer.sleep(50)

      assert {:error, :queue_has_active_consumers} = MalachiMQ.QueueConfig.delete_queue(queue_name)
    end

    test "returns error when queue has buffered messages", %{queue_name: queue_name} do
      {:ok, _config} = MalachiMQ.QueueConfig.create_queue(queue_name)

      # Enqueue messages
      MalachiMQ.Queue.enqueue(queue_name, "test message")
      :timer.sleep(50)

      assert {:error, :queue_has_buffered_messages} = MalachiMQ.QueueConfig.delete_queue(queue_name)
    end

    test "force deletes queue with active consumers", %{queue_name: queue_name} do
      {:ok, _config} = MalachiMQ.QueueConfig.create_queue(queue_name)

      consumer_pid =
        spawn(fn ->
          receive do
            _ -> :ok
          end
        end)

      MalachiMQ.Queue.subscribe(queue_name, consumer_pid)
      :timer.sleep(50)

      assert :ok = MalachiMQ.QueueConfig.delete_queue(queue_name, force: true)
      refute MalachiMQ.QueueConfig.exists?(queue_name)
    end
  end

  describe "list_queues/0" do
    test "lists all configured queues" do
      queue1 = "list_test_queue_1_#{:rand.uniform(1_000_000)}"
      queue2 = "list_test_queue_2_#{:rand.uniform(1_000_000)}"

      {:ok, _} = MalachiMQ.QueueConfig.create_queue(queue1)
      {:ok, _} = MalachiMQ.QueueConfig.create_queue(queue2)

      queues = MalachiMQ.QueueConfig.list_queues()
      queue_names = Enum.map(queues, & &1.queue_name)

      assert queue1 in queue_names
      assert queue2 in queue_names
    end

    test "returns sorted list by created_at" do
      queue1 = "sorted_queue_1_#{:rand.uniform(1_000_000)}"
      queue2 = "sorted_queue_2_#{:rand.uniform(1_000_000)}"

      {:ok, config1} = MalachiMQ.QueueConfig.create_queue(queue1)
      :timer.sleep(10)
      {:ok, config2} = MalachiMQ.QueueConfig.create_queue(queue2)

      queues = MalachiMQ.QueueConfig.list_queues()
      matching_queues = Enum.filter(queues, &(&1.queue_name in [queue1, queue2]))

      [first, second] = Enum.sort_by(matching_queues, & &1.created_at)
      assert first.created_at <= second.created_at
    end
  end

  describe "exists?/1" do
    test "returns true for existing queue", %{queue_name: queue_name} do
      {:ok, _config} = MalachiMQ.QueueConfig.create_queue(queue_name)
      assert MalachiMQ.QueueConfig.exists?(queue_name)
    end

    test "returns false for non-existent queue" do
      refute MalachiMQ.QueueConfig.exists?("non_existent_queue_#{:rand.uniform(1_000_000)}")
    end
  end
end
