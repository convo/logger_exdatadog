import Config

config :logger,
  backends: [
    {LoggerExdatadog.Console, :json}
  ]

config :logger, :json, level: :info
