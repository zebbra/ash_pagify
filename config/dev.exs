import Config

# Configure git hooks. They can be installed manuallu by running `mix git_hooks.install`
config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    pre_push: [
      tasks: [
        {:cmd, "mix check"}
      ]
    ]
  ]

config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/zebbra/ash_pagify",
  # Instructs the tool to manage your mix version in your `mix.exs` file
  # See below for more information
  manage_mix_version?: true,
  # Instructs the tool to manage the version in your README.md
  # Pass in `true` to use `"README.md"` or a string to customize
  manage_readme_version: "README.md",
  version_tag_prefix: "v"
