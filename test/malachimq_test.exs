defmodule MalachiMQTest do
  use ExUnit.Case

  describe "MalachiMQ Application" do
    test "application starts successfully" do
      # Verify that the application module is defined
      assert Code.ensure_loaded?(MalachiMQ.Application)
    end

    test "main modules are available" do
      # Verify core modules are loaded
      assert Code.ensure_loaded?(MalachiMQ.Queue)
      assert Code.ensure_loaded?(MalachiMQ.Auth)
      assert Code.ensure_loaded?(MalachiMQ.AckManager)
      assert Code.ensure_loaded?(MalachiMQ.PartitionManager)
    end
  end
end
