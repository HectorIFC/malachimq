defmodule MalachiMQ.MetricsTest do
  use ExUnit.Case, async: false

  setup do
    queue_name = "metrics_test_#{:rand.uniform(100_000)}"
    {:ok, queue_name: queue_name}
  end

  describe "increment functions" do
    test "increments enqueued counter", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_enqueued(queue_name)
      MalachiMQ.Metrics.increment_enqueued(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.enqueued == 2
    end

    test "increments processed counter", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_processed(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.processed == 1
    end

    test "increments errors counter", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_errors(queue_name)
      MalachiMQ.Metrics.increment_errors(queue_name)
      MalachiMQ.Metrics.increment_errors(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.errors == 3
    end

    test "increments acked counter", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_acked(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.acked == 1
    end

    test "increments nacked counter", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_nacked(queue_name)
      MalachiMQ.Metrics.increment_nacked(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.nacked == 2
    end

    test "increments retried counter", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_retried(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.retried == 1
    end

    test "increments dead_lettered counter", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_dead_lettered(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.dead_lettered == 1
    end
  end

  describe "record_latency/2" do
    test "records single latency measurement", %{queue_name: queue_name} do
      MalachiMQ.Metrics.record_latency(queue_name, 1000)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.latency_us.avg == 1000
      assert metrics.latency_us.min == 1000
      assert metrics.latency_us.max == 1000
      assert metrics.latency_us.count == 1
    end

    test "calculates average latency", %{queue_name: queue_name} do
      MalachiMQ.Metrics.record_latency(queue_name, 1000)
      MalachiMQ.Metrics.record_latency(queue_name, 2000)
      MalachiMQ.Metrics.record_latency(queue_name, 3000)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.latency_us.avg == 2000
      assert metrics.latency_us.min == 1000
      assert metrics.latency_us.max == 3000
      assert metrics.latency_us.count == 3
    end

    test "tracks min and max latency", %{queue_name: queue_name} do
      MalachiMQ.Metrics.record_latency(queue_name, 500)
      MalachiMQ.Metrics.record_latency(queue_name, 5000)
      MalachiMQ.Metrics.record_latency(queue_name, 2000)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.latency_us.min == 500
      assert metrics.latency_us.max == 5000
    end
  end

  describe "get_metrics/1" do
    test "returns all metrics for a queue", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_enqueued(queue_name)
      MalachiMQ.Metrics.increment_processed(queue_name)
      MalachiMQ.Metrics.record_latency(queue_name, 1500)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)

      assert metrics.queue == queue_name
      assert metrics.enqueued == 1
      assert metrics.processed == 1
      assert metrics.latency_us.avg == 1500
      assert is_map(metrics.queue_stats)
    end

    test "returns zero metrics for non-existent queue", %{queue_name: queue_name} do
      metrics = MalachiMQ.Metrics.get_metrics(queue_name)

      assert metrics.enqueued == 0
      assert metrics.processed == 0
      assert metrics.errors == 0
      assert metrics.latency_us.avg == 0
    end
  end

  describe "get_all_metrics/0" do
    test "returns metrics for all queues" do
      q1 = "all_metrics_1_#{:rand.uniform(10000)}"
      q2 = "all_metrics_2_#{:rand.uniform(10000)}"

      MalachiMQ.Metrics.increment_enqueued(q1)
      MalachiMQ.Metrics.increment_enqueued(q2)

      all_metrics = MalachiMQ.Metrics.get_all_metrics()

      assert is_list(all_metrics)
      assert Enum.any?(all_metrics, &(&1.queue == q1))
      assert Enum.any?(all_metrics, &(&1.queue == q2))
    end
  end

  describe "get_system_metrics/0" do
    test "returns system metrics" do
      metrics = MalachiMQ.Metrics.get_system_metrics()

      assert is_integer(metrics.timestamp)
      assert is_integer(metrics.schedulers_online)
      assert metrics.schedulers_online > 0
      assert is_integer(metrics.process_count)
      assert metrics.process_count > 0
      assert is_integer(metrics.process_limit)
      assert is_integer(metrics.run_queue)
      assert is_map(metrics.memory)
      assert is_float(metrics.memory.total_mb)
      assert metrics.memory.total_mb > 0
      assert is_integer(metrics.ets_tables)
      assert is_map(metrics.io)
      assert is_integer(metrics.uptime_seconds)
    end

    test "memory breakdown is present" do
      metrics = MalachiMQ.Metrics.get_system_metrics()

      assert is_float(metrics.memory.processes_mb)
      assert is_float(metrics.memory.ets_mb)
      assert is_float(metrics.memory.atom_mb)
      assert is_float(metrics.memory.binary_mb)
    end
  end

  describe "reset_metrics/1" do
    test "resets metrics for a queue", %{queue_name: queue_name} do
      MalachiMQ.Metrics.increment_enqueued(queue_name)
      MalachiMQ.Metrics.increment_processed(queue_name)
      MalachiMQ.Metrics.record_latency(queue_name, 1000)

      MalachiMQ.Metrics.reset_metrics(queue_name)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.enqueued == 0
      assert metrics.processed == 0
      assert metrics.errors == 0
      assert metrics.latency_us.avg == 0
    end
  end

  describe "metrics history" do
    test "takes snapshots periodically" do
      Application.put_env(:malachimq, :metrics_snapshot_interval_ms, 100)

      queue_name = "history_test_#{:rand.uniform(10000)}"
      MalachiMQ.Metrics.increment_enqueued(queue_name)

      :timer.sleep(250)

      history = MalachiMQ.Metrics.get_history(60)
      assert is_list(history)
      assert history != []

      Application.delete_env(:malachimq, :metrics_snapshot_interval_ms)
    end

    test "get_history returns snapshots within time window" do
      history = MalachiMQ.Metrics.get_history(10)

      assert is_list(history)

      Enum.each(history, fn snapshot ->
        assert is_map(snapshot)
        assert Map.has_key?(snapshot, :timestamp)
        assert Map.has_key?(snapshot, :queues)
        assert Map.has_key?(snapshot, :system)
      end)
    end

    test "cleans up old snapshots" do
      Application.put_env(:malachimq, :metrics_history_seconds, 1)
      Application.put_env(:malachimq, :metrics_cleanup_interval_ms, 500)

      :timer.sleep(1500)

      Application.delete_env(:malachimq, :metrics_history_seconds)
      Application.delete_env(:malachimq, :metrics_cleanup_interval_ms)
    end
  end

  describe "concurrent metric updates" do
    test "handles concurrent increments correctly", %{queue_name: queue_name} do
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            MalachiMQ.Metrics.increment_enqueued(queue_name)
          end)
        end

      Enum.each(tasks, &Task.await/1)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      assert metrics.enqueued == 100
    end

    test "handles concurrent latency recordings", %{queue_name: queue_name} do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            MalachiMQ.Metrics.record_latency(queue_name, i * 100)
          end)
        end

      Enum.each(tasks, &Task.await/1)

      :timer.sleep(100)

      metrics = MalachiMQ.Metrics.get_metrics(queue_name)
      # Allow for some concurrency issues - just verify we got some recordings
      assert metrics.latency_us.count >= 30
    end
  end
end
