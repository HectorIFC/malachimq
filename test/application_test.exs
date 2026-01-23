defmodule MalachiMQ.ApplicationTest do
  use ExUnit.Case, async: false

  describe "application startup" do
    test "application is started" do
      assert Process.whereis(MalachiMQ.Supervisor) != nil
    end

    test "all critical services are running" do
      assert Process.whereis(MalachiMQ.PartitionManager) != nil
      assert Process.whereis(MalachiMQ.Metrics) != nil
      assert Process.whereis(MalachiMQ.Auth) != nil
      assert Process.whereis(MalachiMQ.AckManager) != nil
      assert Process.whereis(MalachiMQ.ConnectionRegistry) != nil
    end

    test "QueueRegistry is available" do
      assert Registry.whereis_name({MalachiMQ.QueueRegistry, {:test, 0}}) == :undefined
    end

    test "QueueSupervisor is running" do
      assert Process.whereis(MalachiMQ.QueueSupervisor) != nil
    end

    test "TaskSupervisor is running" do
      assert Process.whereis(MalachiMQ.TaskSupervisor) != nil
    end
  end

  describe "configuration" do
    test "TCP port is configured" do
      port = Application.get_env(:malachimq, :tcp_port, 4040)
      assert is_integer(port)
      assert port > 0
    end

    test "dashboard port is configured" do
      port = Application.get_env(:malachimq, :dashboard_port, 4041)
      assert is_integer(port)
      assert port > 0
    end

    test "schedulers are configured" do
      schedulers = System.schedulers_online()
      assert schedulers > 0
    end
  end
end
