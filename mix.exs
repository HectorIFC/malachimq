defmodule MalachiMQ.MixProject do
  use Mix.Project

  @version "0.4.4"
  @source_url "https://github.com/HectorIFC/malachimq"

  def project do
    [
      app: :malachimq,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      description: description(),
      package: package(),
      source_url: @source_url,
      test_coverage: [tool: ExCoveralls, threshold: 75]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :crypto, :ssl],
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
