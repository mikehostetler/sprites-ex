defmodule Sprites.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/superfly/sprites-ex"

  def project do
    [
      app: :sprites,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Sprites",
      description: "Elixir SDK for Sprites code container runtime",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl, :inets]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.live": :test
      ]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:gun, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:zoi, "~> 0.17"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "test.live": ["test --include integration --include live"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "Sprites-Ex",
      extras: ["README.md"]
    ]
  end
end
