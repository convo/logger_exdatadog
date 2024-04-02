use Mix.Config

config :logger,
  backends: [
    {LoggerExdatadog.Network, :datadog},
    {LoggerExdatadog.Console, :json}
  ]

config :logger, :datadog,
  level: :debug,
  # :network_only, :console_only, :both
  mode: :network_only,
  api_token: "",
  endpoint: "intake.logs.datadoghq.com",
  port: 10514,
  tls: false,
  fields: %{
    ddsource: "my_project",
    ddtags: "env:staging,version:1.0",
    service: "my_service"
  },
  workers: 2,
  buffer_size: 10_000

config :logger, :json, level: :info
