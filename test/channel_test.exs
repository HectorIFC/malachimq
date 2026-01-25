defmodule MalachiMQ.ChannelTest do
  use ExUnit.Case, async: false
  alias MalachiMQ.Channel

  setup do
    # Ensure channel processes are cleaned up between tests
    on_exit(fn ->
      # Give time for cleanup
      Process.sleep(100)
    end)

    :ok
  end

  describe "publish/3" do
    test "publishes message to channel" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      # Publishing should succeed even without subscribers
      assert :ok = Channel.publish(channel_name, "test payload")
    end

    test "publishes message with headers" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"
      headers = %{"x-priority" => "high", "x-source" => "test"}

      assert :ok = Channel.publish(channel_name, "test payload", headers)
    end
  end

  describe "subscribe/2" do
    test "subscribes to channel" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      assert :ok = Channel.subscribe(channel_name, self())

      stats = Channel.get_stats(channel_name)
      assert stats.exists == true
      assert stats.subscribers == 1
    end

    test "multiple subscribers can subscribe to same channel" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      {:ok, pid1} = Task.start_link(fn -> Process.sleep(5000) end)
      {:ok, pid2} = Task.start_link(fn -> Process.sleep(5000) end)

      assert :ok = Channel.subscribe(channel_name, pid1)
      assert :ok = Channel.subscribe(channel_name, pid2)

      stats = Channel.get_stats(channel_name)
      assert stats.subscribers == 2

      Process.exit(pid1, :normal)
      Process.exit(pid2, :normal)
    end
  end

  describe "publish and receive" do
    test "subscriber receives published message" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      Channel.subscribe(channel_name, self())
      Channel.publish(channel_name, "hello world")

      assert_receive {:channel_message, message}, 1000
      assert message.payload == "hello world"
      assert message.channel == channel_name
      assert is_integer(message.timestamp)
    end

    test "message is delivered to all subscribers" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"
      test_pid = self()

      # Create two subscriber processes
      {:ok, sub1} =
        Task.start_link(fn ->
          Channel.subscribe(channel_name, self())
          send(test_pid, {:ready, self()})

          receive do
            {:channel_message, msg} -> send(test_pid, {:received, self(), msg})
          after
            5000 -> :timeout
          end
        end)

      {:ok, sub2} =
        Task.start_link(fn ->
          Channel.subscribe(channel_name, self())
          send(test_pid, {:ready, self()})

          receive do
            {:channel_message, msg} -> send(test_pid, {:received, self(), msg})
          after
            5000 -> :timeout
          end
        end)

      # Wait for both to be ready
      assert_receive {:ready, ^sub1}, 1000
      assert_receive {:ready, ^sub2}, 1000

      # Publish message
      Channel.publish(channel_name, "broadcast test")

      # Both should receive it
      assert_receive {:received, ^sub1, msg1}, 1000
      assert_receive {:received, ^sub2, msg2}, 1000

      assert msg1.payload == "broadcast test"
      assert msg2.payload == "broadcast test"
    end

    test "message is dropped if no subscribers" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      # Publish without any subscribers
      Channel.publish(channel_name, "dropped message")

      stats = Channel.get_stats(channel_name)
      assert stats.published == 1
      assert stats.dropped == 1
      assert stats.delivered == 0
    end

    test "message includes headers" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"
      headers = %{"priority" => 1, "type" => "alert"}

      Channel.subscribe(channel_name, self())
      Channel.publish(channel_name, "test", headers)

      assert_receive {:channel_message, message}, 1000
      assert message.headers == headers
    end
  end

  describe "unsubscribe/2" do
    test "removes subscriber from channel" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      Channel.subscribe(channel_name, self())
      assert Channel.get_stats(channel_name).subscribers == 1

      Channel.unsubscribe(channel_name, self())
      assert Channel.get_stats(channel_name).subscribers == 0
    end

    test "unsubscribed process no longer receives messages" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      Channel.subscribe(channel_name, self())
      Channel.unsubscribe(channel_name, self())

      Channel.publish(channel_name, "should not receive")

      refute_receive {:channel_message, _}, 500
    end
  end

  describe "get_stats/1" do
    test "returns stats for non-existent channel" do
      stats = Channel.get_stats("non_existent_channel")

      assert stats.exists == false
      assert stats.subscribers == 0
    end

    test "returns stats for existing channel" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      Channel.subscribe(channel_name, self())
      Channel.publish(channel_name, "test 1")
      Channel.publish(channel_name, "test 2")

      stats = Channel.get_stats(channel_name)

      assert stats.exists == true
      assert stats.subscribers == 1
      assert stats.published == 2
      assert stats.delivered == 2
      assert stats.dropped == 0
      assert is_integer(stats.uptime)
    end
  end

  describe "list_subscribers/1" do
    test "returns empty list for channel with no subscribers" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      Channel.publish(channel_name, "trigger creation")

      assert Channel.list_subscribers(channel_name) == []
    end

    test "returns list of subscriber PIDs" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      {:ok, pid1} = Task.start_link(fn -> Process.sleep(5000) end)
      {:ok, pid2} = Task.start_link(fn -> Process.sleep(5000) end)

      Channel.subscribe(channel_name, pid1)
      Channel.subscribe(channel_name, pid2)

      subscribers = Channel.list_subscribers(channel_name)
      assert length(subscribers) == 2
      assert pid1 in subscribers
      assert pid2 in subscribers

      Process.exit(pid1, :normal)
      Process.exit(pid2, :normal)
    end
  end

  describe "kick_subscriber/2" do
    test "removes subscriber and sends notification" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      Channel.subscribe(channel_name, self())
      assert Channel.get_stats(channel_name).subscribers == 1

      assert :ok = Channel.kick_subscriber(channel_name, self())

      # Should receive kick notification
      assert_receive {:kicked_from_channel, ^channel_name}, 1000

      # Should be removed from subscribers
      assert Channel.get_stats(channel_name).subscribers == 0
    end

    test "returns error for non-subscribed process" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      Channel.publish(channel_name, "create channel")

      {:ok, pid} = Task.start_link(fn -> Process.sleep(5000) end)

      assert {:error, :not_subscribed} = Channel.kick_subscriber(channel_name, pid)

      Process.exit(pid, :normal)
    end

    test "returns error for non-existent channel" do
      {:ok, pid} = Task.start_link(fn -> Process.sleep(5000) end)

      assert {:error, :channel_not_found} = Channel.kick_subscriber("non_existent", pid)

      Process.exit(pid, :normal)
    end
  end

  describe "subscriber process monitoring" do
    test "removes subscriber when process dies" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      # Use a task that can be killed safely
      task =
        Task.async(fn ->
          Channel.subscribe(channel_name, self())
          send(self(), :subscribed)

          receive do
            :stop -> :ok
          end
        end)

      # Wait a bit for subscription to complete
      Process.sleep(50)

      assert Channel.get_stats(channel_name).subscribers == 1

      # Stop the task
      Task.shutdown(task, :brutal_kill)
      Process.sleep(100)

      assert Channel.get_stats(channel_name).subscribers == 0
    end
  end

  describe "implicit channel creation" do
    test "channel is created on first publish" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      stats_before = Channel.get_stats(channel_name)
      assert stats_before.exists == false

      Channel.publish(channel_name, "create me")

      stats_after = Channel.get_stats(channel_name)
      assert stats_after.exists == true
    end

    test "channel is created on first subscribe" do
      channel_name = "test_channel_#{:rand.uniform(100_000)}"

      stats_before = Channel.get_stats(channel_name)
      assert stats_before.exists == false

      Channel.subscribe(channel_name, self())

      stats_after = Channel.get_stats(channel_name)
      assert stats_after.exists == true
    end
  end
end
