# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_pagify,
  ash_domains: [],
  env: Mix.env()

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :spark, :formatter,
  remove_parens?: true,
  "Ash.Resource": [
    type: Ash.Resource,
    section_order: [
      :authentication,
      :token,
      :attributes,
      :relationships,
      :calculations,
      :aggregates,
      :state_machine,
      :preparations,
      :actions,
      :changes,
      :pub_sub,
      :code_interface,
      :policies,
      :postgres,
      :graphql,
      :json_api
    ]
  ]

import_config "#{config_env()}.exs"
