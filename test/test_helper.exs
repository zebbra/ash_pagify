ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter], exclude: [pending: true])
ExUnit.start()
