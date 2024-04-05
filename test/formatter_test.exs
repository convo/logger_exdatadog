defmodule FormatterTest do
  use ExUnit.Case, async: false
  alias LoggerExdatadog.Formatter

  defmodule Foo do
    defstruct [:bar]
  end

  defmodule Hello do
    defstruct [:world]
  end

  defimpl Jason.Encoder, for: Hello do
    def encode(%Hello{}, opts) do
      "HELLO_WORLD"
      |> Jason.Encoder.BitString.encode(opts)
    end
  end

  test "Creates and serializes event" do
    message = "Test test"
    event = log(message)

    syslog = Map.get(event, :syslog)

    time = Map.get(syslog, :timestamp)
    assert Map.get(event, :message) == message
    assert Map.get(syslog, :severity) == :info
    assert String.starts_with?(time, "2015-04-19T08:15:03.028")
    assert String.length(time) == 24
  end

  test "Joins extra fields but does not overwrite existing fields" do
    message = "Test the second"
    event = log(message, %{foo: "bar", level: "fail", message: "fail"})

    syslog = Map.get(event, :syslog)
    assert Map.get(event, :message) == message
    assert Map.get(event, :level) == "fail"
    assert Map.get(syslog, :severity) == :info
    assert Map.get(event, :foo) == "bar"
  end

  test "Joins metadata fields but does not overwrite existing fields" do
    message = "Test the second"
    event = log(message, %{}, foo: "bar", level: "fail", message: "fail")

    syslog = Map.get(event, :syslog)
    assert Map.get(event, :message) == message
    assert Map.get(event, :level) == "fail"
    assert Map.get(syslog, :severity) == :info
    assert Map.get(event, :foo) == "bar"
  end

  test "timestamp check" do
    event =
      Formatter.event(:info, "", {{2015, 1, 1}, {0, 0, 0, 0}}, [], %{
        metadata: [],
        fields: %{},
        formatter: & &1
      })

    syslog = Map.get(event, :syslog)
    assert Map.get(syslog, :timestamp) == "2015-01-01T00:00:00.000Z"
  end

  test "Converts event to json" do
    message = "Test the third"
    event = message |> log_json() |> Jason.decode!()

    syslog = Map.get(event, "syslog")
    assert Map.get(event, "message") == message
    assert Map.get(syslog, "severity") == "info"
  end

  test "Formats message" do
    message =
      ["Hello", 32, ~c"wo", ["rl", ~c"d!"]]
      |> log()
      |> Map.get(:message)

    assert message == "Hello world!"
  end

  test "Handle lists such as [1, 2 | 3]" do
    message =
      ["a", "b" | "c"]
      |> log()
      |> Map.get(:message)

    assert message == "abc"
  end

  test "Includes metadata" do
    assert log("Hello", %{}, foo: "Bar")
           |> Map.get(:foo) == "Bar"
  end

  test "Serializes structs to maps" do
    event = log_json("Hello", %{}, foo: %Foo{bar: "baz"}) |> Jason.decode!()
    assert %{"message" => "Hello", "foo" => %{"bar" => "baz"}} = event
  end

  test "Serializes tuples to lists" do
    event = log_json("Hello", %{}, foo: {:bar, :baz}) |> Jason.decode!()
    assert %{"message" => "Hello", "foo" => ["bar", "baz"]} = event
  end

  test "Inspect non-string binaries" do
    binary = <<171, 152, 70, 16, 37>>
    assert String.valid?(binary) == false

    binary_inspected = inspect(binary)
    event = binary |> log_json(%{foo: binary}, bar: binary) |> Jason.decode!()

    assert event["message"] == binary_inspected
    assert event["bar"] == binary_inspected
    assert event["foo"] == binary_inspected
  end

  test "Formatter is used" do
    assert log("Something", %{}, [], &Map.put(&1, :hello, "there"))
           |> Map.get(:hello) == "there"
  end

  test "use existing implementation of Jason.Encoder" do
    event = log_json("Hello", %{}, hello: %Hello{}) |> Jason.decode!()
    assert %{"message" => "Hello", "hello" => "HELLO_WORLD"} = event
  end

  defp log(msg, fields \\ %{}, metadata \\ [], formatter \\ & &1) do
    Formatter.event(:info, msg, {{2015, 4, 19}, {8, 15, 3, 28}}, metadata, %{
      fields: fields,
      formatter: formatter,
      utc_log: false,
      json_library: Jason
    })
  end

  defp log_json(msg, fields \\ %{}, metadata \\ []) do
    {:ok, l} = Formatter.json(log(msg, fields, metadata), Jason)
    l
  end
end
