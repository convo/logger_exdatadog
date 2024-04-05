defmodule LoggerExdatadogNetworkTest do
  use ExUnit.Case, async: false
  require Logger

  @moduledoc """
  Unit tests for TCP logger output.
  """

  test "Happy case" do
    {listener, logger} = new_backend()

    log(logger, "Hello world!")

    msg = recv_and_close(listener)
    :gen_event.stop(logger)

    event = Jason.decode!(msg)
    syslog = event["syslog"]
    assert syslog["severity"] == "info"
    assert event["message"] == "Hello world!"
  end

  describe "Error logging" do
    setup [:log_to_datadog_tcp]

    test "Log message from throw", %{socket: socket} do
      Task.start(fn -> throw("throw up") end)

      msg = recv_all(socket)

      event = Jason.decode!(msg)
      syslog = event["syslog"]
      assert syslog["severity"] == "error"
      assert event["message"] =~ "throw up"
    end

    test "Log message from raise", %{socket: socket} do
      Task.start(fn -> raise "my exception" end)

      msg = recv_all(socket)

      event = Jason.decode!(msg)
      syslog = event["syslog"]
      assert syslog["severity"] == "error"
      assert event["message"] =~ "my exception"
    end

    defmodule Blubb do
      require Logger

      def do_logging() do
        Logger.debug("Can you hear me?")
      end
    end

    test "Log message with a module", %{socket: socket} do
      Blubb.do_logging()

      msg = recv_all(socket)

      event = Jason.decode!(msg)
      syslog = event["syslog"]
      assert syslog["severity"] == "debug"
      assert event["message"] =~ "Can you hear me?"

      if event["mfa"] do
        assert event["mfa"] == ["Elixir.LoggerExdatadogNetworkTest.Blubb", "do_logging", "0"]
      end
    end

    test "Log message from missing FunctionClauseError", %{socket: socket} do
      Task.start(fn ->
        missing_clause = fn :something -> nil end
        missing_clause.(:not_something)
      end)

      msg = recv_all(socket)

      event = Jason.decode!(msg)

      syslog = event["syslog"]
      assert syslog["severity"] == "error"
      assert event["message"] =~ "FunctionClauseError"
    end
  end

  test "TCP log messages end with newline" do
    {listener, logger} = new_backend()

    log(logger, "Hello world!")

    msg = recv_and_close(listener)
    :gen_event.stop(logger)

    assert msg |> String.ends_with?("\n")
  end

  test "Can send several messages" do
    {listener, logger} = new_backend()

    log(logger, "Hello world!")
    log(logger, "Foo?")
    log(logger, "Bar!")

    # Receive all
    {:ok, socket} = :gen_tcp.accept(listener, 1000)
    msg = recv_all(socket)
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(listener)
    :gen_event.stop(logger)

    lines = msg |> String.trim() |> String.split("\n") |> List.to_tuple()
    assert tuple_size(lines) == 3
    assert lines |> elem(0) |> Jason.decode!() |> Map.get("message") == "Hello world!"
    assert lines |> elem(1) |> Jason.decode!() |> Map.get("message") == "Foo?"
    assert lines |> elem(2) |> Jason.decode!() |> Map.get("message") == "Bar!"
  end

  test "Sent messages include metadata" do
    {listener, logger} = new_backend()

    log(logger, "Hello world!", :info, car: "Apple")

    msg = recv_and_close(listener)
    :gen_event.stop(logger)

    event = Jason.decode!(msg)
    assert event["car"] == "Apple"
  end

  test "Sent messages include static fields" do
    opts =
      :logger
      |> Application.get_env(:datadog)
      |> Keyword.put(:fields, %{test_field: "test_value"})

    Application.put_env(:logger, :datadog, opts)

    {listener, logger} = new_backend()

    log(logger, "Hello world!", :info, car: "Lamborghini")

    msg = recv_and_close(listener)
    :gen_event.stop(logger)

    event = Jason.decode!(msg)
    assert event["test_field"] == "test_value"
  end

  test "Formatter formats message" do
    {listener, logger} = new_backend(:datadog_with_formatter)

    log(logger, "Hello formatted world!")

    msg = recv_and_close(listener)
    :gen_event.stop(logger)

    event = Jason.decode!(msg)
    syslog = event["syslog"]
    assert syslog["severity"] == "info"
    assert event["message"] == "Hello formatted world!"
    assert event["added_by_formatter"] == "extra_data"
  end

  defp new_backend(logger_name \\ :datadog) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, {:active, false}, {:packet, 0}, {:reuseaddr, true}])

    {:ok, port} = :inet.port(listener)
    {listener, new_logger(port, logger_name)}
  end

  defp new_logger(port, logger_name) do
    opts = :logger |> Application.get_env(logger_name) |> Keyword.put(:port, "#{port}")
    Application.put_env(:logger, logger_name, opts)

    {:ok, manager} = :gen_event.start_link()
    :gen_event.add_handler(manager, LoggerExdatadog.Network, {LoggerExdatadog.Network, logger_name})
    manager
  end

  defp recv_and_close(listener) do
    {:ok, socket} = :gen_tcp.accept(listener, 1000)
    {:ok, msg} = :gen_tcp.recv(socket, 0, 1000)
    :ok = :gen_tcp.close(socket)
    :ok = :gen_tcp.close(listener)
    msg
  end

  defp recv_all(socket) do
    case :gen_tcp.recv(socket, 0, 100) do
      {:ok, msg} -> msg <> recv_all(socket)
      {:error, :timeout} -> ""
    end
  end

  defp log(logger, msg, level \\ :info, metadata \\ []) do
    ts = {{2017, 1, 1}, {1, 2, 3, 400}}
    :gen_event.notify(logger, {level, logger, {Logger, msg, ts, metadata}})
  end

  defp log_to_datadog_tcp(_context) do
    # Create listener socket
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :line, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)

    # Put port to datadog config
    previous_opts = Application.get_env(:logger, :datadog)
    new_opts = Keyword.put(previous_opts, :port, "#{port}")
    :ok = Application.put_env(:logger, :datadog, new_opts)

    # Switch backends
    {:ok, _pid} = Logger.add_backend({LoggerExdatadog.Network, :datadog}, flush: true)
    :ok = Logger.remove_backend({LoggerExdatadog.Console, :json})

    # Accept connections
    {:ok, client} = :gen_tcp.accept(socket)

    # Revert when finished
    on_exit(fn ->
      :gen_tcp.close(socket)
      Logger.remove_backend({LoggerExdatadog.Network, :datadog})
      Logger.add_backend({LoggerExdatadog.Console, :json})
      :ok = Application.put_env(:logger, :datadog, previous_opts)
    end)

    {:ok, socket: client}
  end
end
