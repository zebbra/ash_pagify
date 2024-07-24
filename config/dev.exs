import Config

config :ash_pagify, AshPagify.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ash_pagify_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
