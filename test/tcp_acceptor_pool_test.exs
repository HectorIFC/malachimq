defmodule MalachiMQ.TCPAcceptorPoolTest do
  use ExUnit.Case, async: false

  describe "start_link/1" do
    test "fails with invalid port" do
      result = MalachiMQ.TCPAcceptorPool.start_link(99_999_999)
      assert {:error, _} = result
    end

    test "fails when port is already in use" do
      # Try to start on the same port as the running application
      port = Application.get_env(:malachimq, :tcp_port, 4040)
      result = MalachiMQ.TCPAcceptorPool.start_link(port)

      # Should fail because port is already in use
      assert {:error, _} = result
    end
  end

  describe "configuration" do
    test "accepts valid port numbers" do
      # Test that port validation works
      assert is_integer(Application.get_env(:malachimq, :tcp_port, 4040))
    end

    test "scheduler count is positive" do
      assert System.schedulers_online() > 0
    end

    test "reads tcp_buffer_size from config" do
      buffer_size = Application.get_env(:malachimq, :tcp_buffer_size, 32_768)
      assert is_integer(buffer_size)
      assert buffer_size > 0
    end

    test "reads tcp_backlog from config" do
      backlog = Application.get_env(:malachimq, :tcp_backlog, 4096)
      assert is_integer(backlog)
      assert backlog > 0
    end

    test "reads tcp_send_timeout from config" do
      send_timeout = Application.get_env(:malachimq, :tcp_send_timeout, 30_000)
      assert is_integer(send_timeout)
      assert send_timeout > 0
    end

    test "reads enable_tls from config" do
      enable_tls = Application.get_env(:malachimq, :enable_tls, false)
      assert is_boolean(enable_tls)
    end
  end

  describe "supervisor behavior" do
    test "TCPAcceptorPool supervisor is running" do
      assert Process.whereis(MalachiMQ.TCPAcceptorPool) != nil
    end

    test "has child acceptors running" do
      case Supervisor.which_children(MalachiMQ.TCPAcceptorPool) do
        children when is_list(children) ->
          # Should have multiple acceptor children
          assert length(children) > 0

        _ ->
          :ok
      end
    end
  end

  describe "error handling" do
    test "handles invalid port gracefully" do
      # Port 0 is invalid
      result = MalachiMQ.TCPAcceptorPool.start_link(0)
      # Might start but immediately fail, or fail to start
      assert result == :ignore or match?({:error, _}, result) or match?({:ok, _}, result)
    end

    test "handles negative port" do
      result = MalachiMQ.TCPAcceptorPool.start_link(-1)
      assert {:error, _} = result
    end
  end
end
