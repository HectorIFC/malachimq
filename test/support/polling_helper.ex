defmodule MalachiMQ.Test.PollingHelper do
  @moduledoc """
  Polling utilities for asynchronous test assertions.

  Provides helpers to wait for conditions to become true within a timeout period.
  """

  @default_timeout 5000
  @default_interval 50

  @doc """
  Waits until a condition becomes true or timeout occurs.

  Polls the given function at regular intervals until it returns a truthy value
  or the timeout is exceeded.

  ## Options

  - `:timeout` - Maximum time to wait in ms (default: 5000)
  - `:interval` - Polling interval in ms (default: 50)

  ## Examples

      # Wait for a process to start
      wait_until(fn -> Process.whereis(MyProcess) != nil end)
      
      # Wait with custom timeout
      wait_until(fn -> queue_ready?() end, timeout: 10_000)
      
      # Wait for a metric to reach a value
      wait_until(fn -> 
        metrics = get_metrics()
        metrics.processed >= 100
      end, timeout: 3000, interval: 100)
  """
  def wait_until(fun, opts \\ []) when is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    interval = Keyword.get(opts, :interval, @default_interval)

    wait_until_loop(fun, timeout, interval, :os.system_time(:millisecond))
  end

  defp wait_until_loop(fun, timeout, interval, start_time) do
    elapsed = :os.system_time(:millisecond) - start_time

    cond do
      elapsed >= timeout ->
        {:error, :timeout}

      fun.() ->
        :ok

      true ->
        Process.sleep(interval)
        wait_until_loop(fun, timeout, interval, start_time)
    end
  end

  @doc """
  Waits until a condition becomes true or timeout occurs, raising on timeout.

  Similar to `wait_until/2` but raises an error on timeout instead of returning
  `{:error, :timeout}`. Useful in test assertions.

  ## Examples

      wait_until!(fn -> Process.whereis(MyProcess) != nil end)
  """
  def wait_until!(fun, opts \\ []) when is_function(fun, 0) do
    case wait_until(fun, opts) do
      :ok ->
        :ok

      {:error, :timeout} ->
        raise "Condition not met within timeout"
    end
  end
end
