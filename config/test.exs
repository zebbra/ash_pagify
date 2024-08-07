import Config

config :ash_pagify,
  ash_domains: [AshPagify.Factory.Domain],
  env: Mix.env()

config :logger, level: :warning

# config :ash, disable_async?: true
config :ash, :validate_api_config_inclusion?, false
config :ash, :validate_api_resource_inclusion?, false

config :junit_formatter,
  report_file: "test-junit-report.xml",
  report_dir: Path.expand("../test/reports", __DIR__),
  include_filename?: true
