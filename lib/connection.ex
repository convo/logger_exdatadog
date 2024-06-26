defmodule LoggerExdatadog.Connection do
  use Connection
  require Logger

  @moduledoc """
  Uses the Connection API to maintain a tcp or ssl connection towards datadog and
  handle connection errors.

  Buffers messages that failed to be sent for any reason, until a maximum buffer
  size is reached after which incoming messages are dropped.
  """
  alias LoggerExdatadog.ConnectionWorker

  @connection_opts [active: false, mode: :binary, keepalive: true, packet: 0]
  @backoff_ms 500

  def start_link(transport, host, port, queue, id \\ 0, timeout \\ 1_000) do
    Connection.start_link(__MODULE__, {transport, host, port, queue, id, timeout})
  end

  @spec send(atom() | pid() | {atom(), any()} | {:via, atom(), any()}, any()) :: any()
  @doc "Send message to datadog backend"
  def send(conn, data, timeout \\ 5_000) do
    Connection.call(conn, {:send, data}, timeout)
  end

  @doc "Close connection"
  def close(conn), do: Connection.call(conn, :close)

  @doc "Update configuration and reconnect"
  def configure(conn, host, port) do
    Connection.call(conn, {:configure, host, port})
  end

  def init({transport, host, port, queue, id, timeout}) do
    ConnectionWorker.start_link(self(), queue)

    state = %{transport: transport, id: id, host: host, port: port, timeout: timeout, sock: nil}
    {:connect, :init, state}
  end

  def connect(
        :init,
        %{transport: transport, id: id, sock: nil, host: host, port: port, timeout: timeout} =
          state
      ) do
    case transport.connect(host, port, @connection_opts, timeout) do
      {:ok, sock} ->
        {:ok, %{state | sock: sock}}

      {:error, reason} ->
        connect_error_log(id, reason, host, port)
        {:backoff, @backoff_ms, state}
    end
  end

  def connect(
        _info,
        %{transport: transport, sock: nil, host: host, port: port, timeout: timeout} = state
      ) do
    case transport.connect(host, port, @connection_opts, timeout) do
      {:ok, sock} ->
        {:ok, %{state | sock: sock}}

      {:error, _reason} ->
        {:backoff, @backoff_ms, state}
    end
  end

  def disconnect(
        info,
        %{transport: transport, id: id, sock: sock, host: host, port: port} = state
      ) do
    if sock != nil do
      :ok = transport.close(sock)
    end

    case info do
      {:close, from} -> Connection.reply(from, :ok)
      {:error, reason} -> disconnect_error_log(id, reason, host, port)
    end

    {:backoff, @backoff_ms, %{state | sock: nil}}
  end

  # Drop message and attempt to reconnect if no connection is open
  def handle_call({:send, _data}, _from, %{sock: nil} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:send, data}, _from, %{id: id, sock: sock, transport: transport} = state) do
    case transport.send(sock, data) do
      :ok ->
        {:reply, :ok, state}

      {:error, :closed} = error ->
        {:disconnect, error, error, state}

      {:error, reason} = error ->
        send_error_log(id, reason)
        {:disconnect, error, error, state}
    end
  end

  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call({:configure, host, port}, from, state) do
    {:disconnect, {:close, from}, %{state | host: host, port: port}}
  end

  def terminate(_, %{sock: sock, transport: transport}) do
    if sock != nil do
      :ok = transport.close(sock)
    end
  end

  defp connect_error_log(id, reason, host, port) do
    reason = :inet.format_error(reason)
    IO.puts("#{__MODULE__}[#{id}]: #{host}:#{inspect(port)} connection failed: #{reason}")
  end

  defp disconnect_error_log(id, :closed, host, port) do
    IO.puts("#{__MODULE__}[#{id}]: #{host}:#{inspect(port)} connection closed")
  end

  defp disconnect_error_log(id, reason, host, port) do
    reason = :inet.format_error(reason)
    IO.puts("#{__MODULE__}[#{id}]: #{host}:#{inspect(port)} connection error: #{reason}")
  end

  defp send_error_log(id, reason) do
    reason = :inet.format_error(reason)
    IO.puts("#{__MODULE__}[#{id}]: error sending over TCP: #{reason}")
  end
end
