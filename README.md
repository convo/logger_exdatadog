# LoggerExdatadog

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `logger_exdatadog` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:logger_exdatadog, "~> 1.0.0"}
  ]
end
```

Configuration:

```elixir
config :logger, :datadog,
  level: :info,
  mode: :network_only,
  api_token: "",
  endpoint: "intake.logs.datadoghq.com",
  port: 10514,
  tls: false,
  fields: %{
    ddsource: "my_project",
    ddtags: "env:prodaction,version:1.0",
    service: "my_service"
  },
  json_library: Jason,
  workers: 2,
  buffer_size: 20_000
```

Coverage:

```elixir
Finished in 2.0 seconds (0.00s async, 2.0s sync)
33 tests, 0 failures

Randomized with seed 727695
----------------
COV    FILE                                        LINES RELEVANT   MISSED
 59.5% lib/connection.ex                             137       37       15
100.0% lib/connection_worker.ex                       18        4        0
 93.0% lib/formatter.ex                              152       43        3
 73.9% lib/logger_exdatadog_console.ex                85       23        6
 77.8% lib/logger_exdatadog_network.ex               144       45       10
[TOTAL]  77.6%
```
