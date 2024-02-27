defmodule LoggerExdatadog.Connection.Worker do
  @moduledoc """
  Worker that reads log messages from a BlockingQueue and writes them to
  datadog using a TCP/SSL connection.
  """

  def start_link(conn, queue) do
    spawn_link(fn -> consume_messages(conn, queue) end)
  end

  defp consume_messages(conn, queue) do
    msg = BlockingQueue.pop(queue)
    LoggerExdatadog.Connection.send(conn, msg, 60_000)
    consume_messages(conn, queue)
  end
end
