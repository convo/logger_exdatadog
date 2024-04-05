import Config

config :logger,
  backends: [
    {LoggerExdatadog.Console, :json}
  ]

config :logger, :json, level: :info

config :logger, :datadog,
  level: :debug,
  endpoint: "localhost",
  port: 10514,
  fields: %{
    ddsource: "my_project",
    ddtags: "env:test,version:1.0",
    service: "my_service"
  },
  workers: 1,
  buffer_size: 10_000

config :logger, :datadog_with_formatter,
  level: :debug,
  endpoint: "localhost",
  port: 10514,
  fields: %{
    ddsource: "my_project",
    ddtags: "env:test,version:1.0",
    service: "my_service"
  },
  workers: 1,
  buffer_size: 10_000,
  formatter: fn event -> event |> Map.put(:added_by_formatter, "extra_data") end
