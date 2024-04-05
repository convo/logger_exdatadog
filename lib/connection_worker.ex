defmodule LoggerExdatadog.ConnectionWorker do
  @moduledoc """
  Worker that reads log messages from a BlockingQueue and writes them to
  datadog using a TCP/SSL connection.
  """

  alias LoggerExdatadog.Connection

  def start_link(conn, queue) do
    spawn_link(fn -> consume_messages(conn, queue) end)
  end

  defp consume_messages(conn, queue) do
    msg = BlockingQueue.pop(queue)
    Connection.send(conn, msg, 60_000)
    consume_messages(conn, queue)
  end
end
