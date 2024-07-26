defmodule AshPagify.MixProject do
  use Mix.Project

  @description """
  Adds full-text search, scoping, filtering, ordering, and pagination APIs for the Ash Framework.
  """

  @version "0.1.0"

  def project do
    [
      app: :ash_pagify,
      version: @version,
      elixir: "~> 1.17",
      deps: deps(),
      description: @description,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      package: package(),

      # Dialyzer
      dializyer: [plt_add_apps: :mix],

      # Docs
      source_url: "https://github.com/zebbra/ash_pagify",
      homepage_url: "https://hexdocs.pm/ash_pagify",
      docs: docs()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application, do: []

  # Configuation for the OTP compiler.
  #
  # Type `mix help compile.elixir` for more information.
  defp elixirc_paths(:test), do: elixirc_paths(:dev) ++ ["test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Hex package manager configuration.
  #
  # Type `mix help hex.config` for more information.
  def package do
    [
      name: "ash_pagify",
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      links: %{
        "GitHub" => "https://github.com/zebbra/ash_pagify"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        {"README.md", title: "Home"},
        "CHANGELOG.md"
      ],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md"
      ],
      nest_modules_by_prefix: [
        AshPagify.Error,
        AshPagify.Components
      ],
      groups_for_modules: [
        Core: [
          AshPagify,
          AshPagify.Meta,
          AshPagify.Misc,
          AshPagify.Tsearch,
          AshPagify.Validation
        ],
        Components: [
          AshPagify.Components,
          AshPagify.Components.Pagination,
          AshPagify.Components.Table
        ],
        Filters: [
          AshPagify.FilterForm
        ],
        Errors: [
          AshPagify.Error,
          ~r/AshPagify.Error\./
        ]
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
      {:ex_check, "~> 0.16", only: [:dev, :test]},
      {:credo, "~> 1.7.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.3", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1.4", only: [:dev, :test], runtime: false},
      {:assertions, "~> 0.20.1", only: :test},
      {:styler, "~> 0.11.9", only: [:dev, :test], runtime: false},
      {:junit_formatter, "~> 3.3", only: :test},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:floki, ">= 0.36.0", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.6.1", only: [:dev]},
      {:git_hooks, "~> 0.7.3", only: [:dev], runtime: false},

      # Utilities and Helpers
      # TODO Remove upon Ash v3 migration
      {:splode, "~> 0.2.4"},

      # Documentation
      {:ex_doc, "~> 0.34.2", runtime: false}
    ]
  end

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
        "check"
      ]
    ]
  end
end
