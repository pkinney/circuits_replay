defmodule Replay.MixProject do
  use Mix.Project

  def project do
    [
      app: :replay,
      version: "0.1.0",
      elixir: "~> 1.12",
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: ~w(mimic resolve)a]
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
      {:circuits_gpio, "~> 1.0", optional: true},
      {:resolve, "~> 0.1.0", optional: true},
      {:mimic, "~> 1.7", optional: true},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.19", only: :dev}
    ]
  end

  defp description do
    """
    Testing library for mocking Circuits libraries through a sequence of steps.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Powell Kinney"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/pkinney/circuits_replay",
        "Docs" => "https://hexdocs.pm/replay/Replay.html"
      }
    ]
  end

  defp aliases do
    [
      validate: [
        "clean",
        "compile --warnings-as-error",
        "format --check-formatted",
        "credo",
        "dialyzer"
      ]
    ]
  end
end
