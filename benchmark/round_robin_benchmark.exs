defmodule RoundRobinBenchmark do
  @moduledoc """
  Benchmark to compare different round-robin implementations
  Scenario: 1 million messages to 1000 consumers
  """

  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("BENCHMARK: 1 million messages -> 1000 consumers")
    IO.puts(String.duplicate("=", 80) <> "\n")

    num_messages = 1_000_000
    num_consumers = 1_000

    # Prepare fake consumers (simulated PIDs)
    consumers = for _i <- 1..num_consumers, do: spawn(fn -> :timer.sleep(:infinity) end)
    
    IO.puts("Setup:")
    IO.puts("  - Messages: #{format_number(num_messages)}")
    IO.puts("  - Consumers: #{format_number(num_consumers)}")
    IO.puts("  - Messages per consumer: #{format_number(div(num_messages, num_consumers))}")
    IO.puts("")

    # Test 1: List (current implementation)
    IO.puts("📊 Test 1: List (current implementation)")
    {time_list, _result} = :timer.tc(fn ->
      benchmark_list(consumers, num_messages)
    end)
    print_results("List", time_list, num_messages)

    # Test 2: Tuple (O(1) access)
    IO.puts("\n📊 Test 2: Tuple (O(1) access)")
    {time_tuple, _result} = :timer.tc(fn ->
      benchmark_tuple(consumers, num_messages)
    end)
    print_results("Tuple", time_tuple, num_messages)

    # Test 3: Array (Erlang array)
    IO.puts("\n📊 Test 3: Array (Erlang :array)")
    {time_array, _result} = :timer.tc(fn ->
      benchmark_array(consumers, num_messages)
    end)
    print_results("Array", time_array, num_messages)

    # Test 4: ETS ordered_set with numeric index
    IO.puts("\n📊 Test 4: ETS :ordered_set (numeric index)")
    {time_ets, _result} = :timer.tc(fn ->
      benchmark_ets_indexed(consumers, num_messages)
    end)
    print_results("ETS indexed", time_ets, num_messages)

    # Final comparison
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("PERFORMANCE COMPARISON")
    IO.puts(String.duplicate("=", 80))
    
    results = [
      {"List (current)", time_list},
      {"Tuple", time_tuple},
      {"Array", time_array},
      {"ETS indexed", time_ets}
    ]
    
    fastest = Enum.min_by(results, fn {_, time} -> time end)
    {fastest_name, fastest_time} = fastest
    
    IO.puts("\n🏆 Fastest: #{fastest_name}\n")
    
    Enum.each(results, fn {name, time} ->
      speedup = time / fastest_time
      slower_pct = (speedup - 1.0) * 100
      
      symbol = if name == fastest_name, do: "🏆", else: "  "
      
      IO.puts("#{symbol} #{String.pad_trailing(name, 20)} " <>
              "#{format_time(time)} " <>
              if name == fastest_name do
                "(baseline)"
              else
                "(#{:erlang.float_to_binary(speedup, decimals: 2)}x - #{:erlang.float_to_binary(slower_pct, decimals: 1)}% slower)"
              end)
    end)

    # Recommendation
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("RECOMMENDATION")
    IO.puts(String.duplicate("=", 80))
    
    {_list_name, list_time} = Enum.find(results, fn {name, _} -> name == "List (current)" end)
    speedup_tuple = list_time / elem(Enum.find(results, fn {name, _} -> name == "Tuple" end), 1)
    
    if speedup_tuple > 2.0 do
      IO.puts("\n⚠️  OPTIMIZE: Tuple is #{:erlang.float_to_binary(speedup_tuple, decimals: 1)}x faster!")
      IO.puts("    Recommendation: Switch to tuple for > 500 consumers")
    else
      IO.puts("\n✅ OK: List is adequate for this scenario")
      IO.puts("    Performance difference is acceptable (< 2x)")
    end
    
    # Cleanup
    Enum.each(consumers, &Process.exit(&1, :kill))
  end

  # Implementation 1: List (current)
  defp benchmark_list(consumers, num_messages) do
    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, 0)
    
    for _ <- 1..num_messages do
      current_index = :atomics.get(counter, 1)
      consumer_index = rem(current_index, length(consumers))
      _consumer_pid = Enum.at(consumers, consumer_index)
      :atomics.add(counter, 1, 1)
    end
  end

  # Implementation 2: Tuple
  defp benchmark_tuple(consumers, num_messages) do
    consumers_tuple = List.to_tuple(consumers)
    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, 0)
    num_consumers = tuple_size(consumers_tuple)
    
    for _ <- 1..num_messages do
      current_index = :atomics.get(counter, 1)
      consumer_index = rem(current_index, num_consumers)
      _consumer_pid = elem(consumers_tuple, consumer_index)
      :atomics.add(counter, 1, 1)
    end
  end

  # Implementation 3: Array
  defp benchmark_array(consumers, num_messages) do
    consumers_array = :array.from_list(consumers)
    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, 0)
    num_consumers = length(consumers)
    
    for _ <- 1..num_messages do
      current_index = :atomics.get(counter, 1)
      consumer_index = rem(current_index, num_consumers)
      _consumer_pid = :array.get(consumer_index, consumers_array)
      :atomics.add(counter, 1, 1)
    end
  end

  # Implementation 4: ETS with numeric index
  defp benchmark_ets_indexed(consumers, num_messages) do
    table = :ets.new(:consumers, [:ordered_set, :public])
    
    # Populate table with numeric index
    consumers
    |> Enum.with_index()
    |> Enum.each(fn {pid, index} ->
      :ets.insert(table, {index, pid})
    end)
    
    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, 0)
    num_consumers = length(consumers)
    
    for _ <- 1..num_messages do
      current_index = :atomics.get(counter, 1)
      consumer_index = rem(current_index, num_consumers)
      [{^consumer_index, _consumer_pid}] = :ets.lookup(table, consumer_index)
      :atomics.add(counter, 1, 1)
    end
    
    :ets.delete(table)
  end

  defp print_results(_name, time_us, num_messages) do
    time_ms = time_us / 1_000
    time_s = time_ms / 1_000
    throughput = num_messages / time_s
    latency_ns = (time_us * 1_000) / num_messages
    
    IO.puts("  Total time: #{format_time(time_us)}")
    IO.puts("  Throughput: #{format_number(round(throughput))} msgs/s")
    IO.puts("  Average latency: #{:erlang.float_to_binary(latency_ns, decimals: 2)} ns/msg")
  end

  defp format_time(microseconds) do
    cond do
      microseconds < 1_000 ->
        "#{round(microseconds)} μs"
      microseconds < 1_000_000 ->
        "#{:erlang.float_to_binary(microseconds / 1_000, decimals: 2)} ms"
      true ->
        "#{:erlang.float_to_binary(microseconds / 1_000_000, decimals: 3)} s"
    end
  end

  defp format_number(num) when num >= 1_000_000 do
    "#{:erlang.float_to_binary(num / 1_000_000, decimals: 2)}M"
  end
  defp format_number(num) when num >= 1_000 do
    "#{:erlang.float_to_binary(num / 1_000, decimals: 2)}K"
  end
  defp format_number(num), do: "#{num}"
end

# Execute benchmark
RoundRobinBenchmark.run()
