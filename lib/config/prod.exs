use Mix.Config

config :logger,
  backends: [
    {LoggerExdatadog.Network, :datadog},
    {LoggerExdatadog.Console, :json}
  ]

config :logger, :datadog,
  level: :debug,
  mode: :network_only, # :network_only, :console_only, :both
  api_token: "",
  endpoint: "intake.logs.datadoghq.com",
  port: "10514",
  tls: false,
  fields: %{appid: "datadog-json"},
  workers: 2,
  buffer_size: 10_000

config :logger, :json, level: :info
