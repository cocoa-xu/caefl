defmodule Caefl.MixProject do
  use Mix.Project

  def project do
    [
      app: :caefl,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nx, "~> 0.2", override: true},
      {:torchx, "~> 0.2"},
      {:scidata, "~> 0.1", github: "elixir-nx/scidata"}
    ]
  end
end
