defmodule MalachiMQ.PartitionManagerTest do
  use ExUnit.Case, async: true

  describe "get_partition/1" do
    test "returns consistent partition for same queue name" do
      {name, partition1} = MalachiMQ.PartitionManager.get_partition("test_queue")
      {name, partition2} = MalachiMQ.PartitionManager.get_partition("test_queue")

      assert partition1 == partition2
      assert name == "test_queue"
    end

    test "distributes different queues across partitions" do
      partitions =
        for i <- 1..100 do
          {_name, partition} = MalachiMQ.PartitionManager.get_partition("queue_#{i}")
          partition
        end

      unique_partitions = Enum.uniq(partitions)
      assert length(unique_partitions) > 1
    end

    test "returns integer partition number" do
      {_name, partition} = MalachiMQ.PartitionManager.get_partition("test")
      assert is_integer(partition)
      assert partition >= 0
    end
  end

  describe "get_partition_count/0" do
    test "returns total number of partitions" do
      count = MalachiMQ.PartitionManager.get_partition_count()
      assert is_integer(count)
      assert count > 0
    end

    test "partition count matches expected calculation" do
      schedulers = System.schedulers_online()
      multiplier = Application.get_env(:malachimq, :partition_multiplier, 100)
      expected = schedulers * multiplier

      assert MalachiMQ.PartitionManager.get_partition_count() == expected
    end
  end
end
