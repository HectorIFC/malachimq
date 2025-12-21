defmodule MalachimqTest do
  use ExUnit.Case
  doctest Malachimq

  test "greets the world" do
    assert Malachimq.hello() == :world
  end
end
