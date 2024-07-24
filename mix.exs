defmodule AshPagify.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_pagify,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps(),
      preferred_cli_env: [
        "test.watch": :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Ash Framework
      {:ash, "~> 2.21.15"},
      {:ash_phoenix, "~> 1.3.7"},
      {:ash_postgres, "~> 1.5.30"},
      {:ash_uuid, "~> 0.7.0"},

      # Phoenix Framework
      {:phoenix, "~> 1.7.14"},

      # Testing and Linting
      {:credo, "~> 1.7.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1.4", only: [:dev, :test], runtime: false},
      {:assertions, "~> 0.20.1", only: :test},
      {:styler, "~> 0.11.9", only: [:dev, :test], runtime: false},
      {:junit_formatter, "~> 3.3", only: :test},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:floki, ">= 0.36.0", only: :test},

      # Utilities and Helpers
      # TODO Remove upon Ash v3 migration
      {:splode, "~> 0.2.4"},

      # Documentation
      {:ex_doc, "~> 0.34.2", runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_), do: ["lib"]

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      # Setup Project
      setup: [
        "deps.get",
        "lint",
        "docs"
      ],

      # Run linters
      lint: [
        "compile --all-warnings --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "deps.audit"
      ]
    ]
  end
end
