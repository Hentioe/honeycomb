defmodule Honeycomb.MixProject do
  use Mix.Project

  def project do
    [
      app: :honeycomb,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "A scheduling system and result collection center for asynchronous/background tasks.",
      package: package(),
      source_url: "https://github.com/Hentioe/honeycomb",
      homepage_url: "https://github.com/Hentioe/honeycomb",
      docs: [
        # The main page in the docs
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Hentioe/honeycomb"}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger] ++ extra_applications(Mix.env()),
      mod: {Honeycomb.Application, []}
    ]
  end

  defp extra_applications(:dev) do
    [:wx, :observer, :runtime_tools]
  end

  defp extra_applications(_) do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.32", only: :dev, runtime: false}
    ]
  end
end
