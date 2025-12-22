defmodule MalachiMQ.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/HectorIFC/malachimq"

  def project do
    [
      app: :malachimq,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      description: description(),
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :crypto],
      mod: {MalachiMQ.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end

  defp releases do
    [
      malachimq: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end

  defp description do
    "A high-performance message queue written in Elixir"
  end

  defp package do
    [
      name: "malachimq",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
