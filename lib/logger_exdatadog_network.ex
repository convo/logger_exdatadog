defmodule LoggerExdatadog.Network do
  @moduledoc """
  Logger backend which sends logs to datadog via TCP/SSL in JSON format.
  """

  @behaviour :gen_event

  alias LoggerExdatadog.{Connection, Formatter}

  @datadog_endpoint "intake.logs.datadoghq.com"
  @datadog_tcp_port 10514

  @doc false
  def init({__MODULE__, name}) do
    if user = Process.whereis(:user) do
      Process.group_leader(self(), user)
      {:ok, configure(name, [])}
    else
      {:error, :ignore}
    end
  end

  @doc false
  def handle_call({:configure, opts}, %{name: name}) do
    {:ok, :ok, configure(name, opts)}
  end

  @doc false
  def handle_info(_msg, state) do
    {:ok, state}
  end

  @doc false
  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event(level, msg, ts, md, state)
    end

    {:ok, state}
  end

  @doc false
  def terminate(_reason, _state) do
    :ok
  end

  @doc false
  def code_change(_old, state, _extra) do
    {:ok, state}
  end

  defp log_event(level, msg, ts, md, %{json_library: json_lib} = state) do
    event = Formatter.event(level, msg, ts, md, state)

    case Formatter.json(event, json_lib) do
      {:ok, log} ->
        send_log(log, state)

      {:error, reason} ->
        IO.puts("Failed to serialize event. error: #{inspect(reason)}, event: #{inspect(event)}")
    end
  end

  defp send_log(log, %{api_token: token, queue: queue}) do
    BlockingQueue.push(queue, [token, " ", log, "\r", "\n"])
  end

  defp configure(name, opts) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level = Keyword.get(opts, :level) || :debug

    api_token = opts |> Keyword.get(:api_token, "")
    host = opts |> Keyword.get(:endpoint, @datadog_endpoint) |> env_var |> to_charlist
    port = opts |> Keyword.get(:port, @datadog_tcp_port) |> env_var |> to_int
    transport = transport(opts)
    fields = Keyword.get(opts, :fields) || %{}
    workers = Keyword.get(opts, :workers) || 2
    worker_pool = Keyword.get(opts, :worker_pool) || nil
    buffer_size = Keyword.get(opts, :buffer_size) || 10_000
    json_lib = Keyword.get(opts, :json_library, Jason)

    formatter =
      case LoggerExdatadog.Formatter.resolve_formatter_config(Keyword.get(opts, :formatter)) do
        {:ok, fun} ->
          fun

        {:error, bad_formatter} ->
          raise "Bad formatter configured for :logger, #{name} -- #{inspect(bad_formatter)}"
      end

    # Close previous worker pool
    if worker_pool != nil do
      :ok = Supervisor.stop(worker_pool)
    end

    # Create new queue and worker pool
    {:ok, queue} = BlockingQueue.start_link(buffer_size)

    children = 1..workers |> Enum.map(&network_worker(&1, transport, host, port, queue))
    {:ok, worker_pool} = Supervisor.start_link(children, strategy: :one_for_one)

    %{
      api_token: api_token,
      transport: transport,
      level: level,
      host: host,
      port: port,
      fields: fields,
      name: name,
      queue: queue,
      worker_pool: worker_pool,
      formatter: formatter,
      json_library: json_lib
    }
  end

  defp network_worker(id, transport, host, port, queue) do
    %{
      id: id,
      start: {Connection, :start_link, [transport, host, port, queue, id]}
    }
  end

  defp transport(opts) do
    case Keyword.get(opts, :tls, false) do
      true -> :ssl
      false -> :gen_tcp
    end
  end

  defp env_var({:system, var, default}), do: System.get_env(var) || default
  defp env_var({:system, var}), do: System.get_env(var)
  defp env_var(value), do: value

  defp to_int(val) when is_integer(val), do: val
  defp to_int(val), do: val |> Integer.parse() |> elem(0)
end
