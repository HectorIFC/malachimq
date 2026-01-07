defmodule MalachiMQTest do
  use ExUnit.Case

  describe "MalachiMQ Application" do
    test "application starts successfully" do
      assert Code.ensure_loaded?(MalachiMQ.Application)
    end

    test "main modules are available" do
      assert Code.ensure_loaded?(MalachiMQ.Queue)
      assert Code.ensure_loaded?(MalachiMQ.Auth)
      assert Code.ensure_loaded?(MalachiMQ.AckManager)
      assert Code.ensure_loaded?(MalachiMQ.PartitionManager)
    end
  end
end
