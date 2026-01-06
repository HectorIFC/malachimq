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
      # Runtime dependencies
      {:jason, "~> 1.4"},
      {:argon2_elixir, "~> 4.0"},

      # Development and test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
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
