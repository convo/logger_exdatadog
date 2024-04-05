defmodule LoggerExdatadog.Formatter do
  @moduledoc """
  This module contains functions for generating and serializing logs events.
  """

  @skipped_metadata_keys [:domain, :erl_level, :gl, :time]

  @doc "Generate a log event from log data"
  def event(level, msg, ts, meta_data, %{
        fields: fields,
        formatter: formatter
      }) do
    normalized_meta_data = normalize_metadata(meta_data)

    fields
    |> format_fields(normalized_meta_data, %{
      message: to_string(msg),
      logger: %{
        thread_name: inspect(Map.get(normalized_meta_data, :pid)),
        method_name: method_name(normalized_meta_data),
        line: Map.get(normalized_meta_data, :line)
      },
      syslog: %{
        hostname: node_hostname(),
        severity: level,
        timestamp: format_timestamp(ts)
      }
    })
    |> formatter.()
  end

  @doc "Serialize a log event to a JSON string"
  def json(event, json_encoder \\ Jason) do
    event |> pre_encode(json_encoder) |> json_encoder.encode()
  end

  defp normalize_metadata(metadata) do
    metadata
    |> format_metadata()
    |> skip_metadata_keys()
  end

  defp format_fields(fields, normalized_meta_data, field_overrides) do
    normalized_meta_data
    |> Map.merge(fields)
    |> Map.merge(field_overrides)
  end

  defp format_metadata(metadata) do
    metadata
    |> Enum.into(%{})
  end

  defp skip_metadata_keys(metadata) do
    metadata
    |> Map.drop(@skipped_metadata_keys)
  end

  def resolve_formatter_config(formatter_spec, default_formatter \\ & &1) do
    # Find an appropriate formatter, if possible, from this config spec.
    case formatter_spec do
      {module, function} ->
        if Keyword.has_key?(module.__info__(:functions), function) do
          {:ok, &apply(module, function, [&1])}
        else
          {:error, {module, function}}
        end

      fun when is_function(fun) ->
        {:ok, fun}

      nil ->
        {:ok, default_formatter}

      bad_formatter ->
        {:error, bad_formatter}
    end
  end

  # Functions for generating timestamp
  defp format_timestamp({date, time}) do
    [format_date(date), ?T, format_time(time), ?Z]
    |> IO.iodata_to_binary()
  end

  defp format_time({hh, mi, ss, ms}) do
    [pad2(hh), ?:, pad2(mi), ?:, pad2(ss), ?., pad3(ms)]
  end

  defp format_date({yy, mm, dd}) do
    [Integer.to_string(yy), ?-, pad2(mm), ?-, pad2(dd)]
  end

  defp pad2(int) when int < 10, do: [?0, Integer.to_string(int)]
  defp pad2(int), do: Integer.to_string(int)

  defp pad3(int) when int < 10, do: [?0, ?0, Integer.to_string(int)]
  defp pad3(int) when int < 100, do: [?0, Integer.to_string(int)]
  defp pad3(int), do: Integer.to_string(int)

  # traverse data and stringify special Elixir/Erlang terms
  defp pre_encode(it, _json_encoder) when is_pid(it), do: inspect(it)
  defp pre_encode(it, _json_encoder) when is_integer(it), do: inspect(it)
  defp pre_encode(it, _json_encoder) when is_function(it), do: inspect(it)

  defp pre_encode(it, json_encoder) when is_list(it),
    do: Enum.map(it, &pre_encode(&1, json_encoder))

  defp pre_encode(it, json_encoder) when is_tuple(it),
    do: pre_encode(Tuple.to_list(it), json_encoder)

  defp pre_encode(%module{} = it, json_encoder) do
    try do
      :ok = Protocol.assert_impl!(Module.concat(json_encoder, Encoder), module)
      it
    rescue
      ArgumentError -> pre_encode(Map.from_struct(it), json_encoder)
    end
  end

  defp pre_encode(it, json_encoder) when is_map(it),
    do:
      Enum.into(it, %{}, fn {k, v} ->
        {pre_encode(k, json_encoder), pre_encode(v, json_encoder)}
      end)

  defp pre_encode(it, _json_encoder) when is_binary(it) do
    it
    |> String.valid?()
    |> case do
      true -> it
      false -> inspect(it)
    end
  end

  defp pre_encode(it, _json_encoder), do: it

  defp node_hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp method_name(metadata) do
    function = Map.get(metadata, :function)
    module = Map.get(metadata, :module)

    format_function(module, function)
  end

  defp format_function(nil, function), do: function
  defp format_function(module, function), do: "#{inspect(module)}.#{function}"
end
