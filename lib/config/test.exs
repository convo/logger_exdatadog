use Mix.Config

config :logger,
  backends: [
    {LoggerExdatadog.Console, :json}
  ]

config :logger, :json, level: :info

config :logger, :datadog,
  level: :debug,
  host: "localhost",
  fields: %{appid: "datadog-json"},
  workers: 1,
  buffer_size: 10_000

config :logger, :datadog_formatter,
  level: :debug,
  host: "localhost",
  fields: %{appid: "datadog-json"},
  workers: 1,
  buffer_size: 10_000,
  formatter: fn event -> event |> Map.put(:added_by_formatter, "extra_data") end
