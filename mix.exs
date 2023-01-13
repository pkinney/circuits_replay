defmodule Replay.MixProject do
  use Mix.Project

  def project do
    [
      app: :replay,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_uart, "~> 1.0", optional: true},
      {:circuits_i2c, "~> 1.0", optional: true},
      {:resolve, "~> 0.1.0", optional: true},
      {:mimic, "~> 1.7", optional: true}
    ]
  end
end
