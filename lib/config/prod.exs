use Mix.Config

config :logger,
  backends: [
    {LoggerExdatadog.Network, :datadog},
    {LoggerExdatadog.Console, :json}
  ]

config :logger, :datadog,
  level: :debug,
  host: System.get_env("DATADOG_HOST") || "localhost",
  port: System.get_env("DATADOG_PORT") || "4560",
  fields: %{appid: "datadog-json"},
  workers: 2,
  buffer_size: 10_000

config :logger, :json, level: :info
