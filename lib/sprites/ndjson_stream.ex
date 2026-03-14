defmodule Sprites.NDJSONStream do
  @moduledoc false

  alias Sprites.{Client, Error, HTTP}

  @type parser_fun :: (map() -> {:ok, term()} | {:error, term()} | term())

  @default_connect_timeout 10_000
  @default_chunk_timeout 60_000

  @spec request(Client.t(), :get | :post | :put | :delete, String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def request(%Client{} = client, method, path, opts \\ []) do
    parser = Keyword.get(opts, :parser, fn event -> event end)
    params = Keyword.get(opts, :params, [])
    extra_headers = Keyword.get(opts, :headers, [])
    success_statuses = Keyword.get(opts, :success, 200..299)
    connect_timeout = Keyword.get(opts, :connect_timeout, @default_connect_timeout)
    chunk_timeout = Keyword.get(opts, :chunk_timeout, @default_chunk_timeout)

    {request_tuple, request_headers} =
      build_request(client, method, path, params, extra_headers, opts)

    request_opts = [sync: false, stream: {:self, :once}]

    case :httpc.request(method, request_tuple, [{:timeout, :infinity}], request_opts) do
      {:ok, request_id} ->
        bootstrap_stream(
          request_id,
          request_headers,
          parser,
          success_statuses,
          connect_timeout,
          chunk_timeout
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bootstrap_stream(
         request_id,
         request_headers,
         parser,
         success_statuses,
         connect_timeout,
         chunk_timeout
       ) do
    receive do
      {:http, {^request_id, :stream_start, _headers, stream_pid}} ->
        :ok = :httpc.stream_next(stream_pid)

        state = %{
          request_id: request_id,
          stream_pid: stream_pid,
          parser: parser,
          buffer: "",
          pending: [],
          done?: false,
          chunk_timeout: chunk_timeout
        }

        {:ok, Stream.resource(fn -> state end, &next_chunk/1, &cleanup/1)}

      {:http, {^request_id, {{_http_version, status, _reason}, response_headers, body}}} ->
        case HTTP.success?(status, success_statuses) do
          true ->
            {:ok, parse_non_stream_body(body, parser)}

          false ->
            body_binary = IO.iodata_to_binary(body)

            case Error.parse_api_error(status, body_binary, request_headers ++ response_headers) do
              {:ok, %Error.APIError{} = api_error} ->
                {:error, api_error}

              {:ok, nil} ->
                {:error, {:http_status, status, body_binary}}
            end
        end

      {:http, {^request_id, {:error, reason}}} ->
        {:error, reason}
    after
      connect_timeout ->
        :httpc.cancel_request(request_id)
        {:error, :stream_connect_timeout}
    end
  end

  defp next_chunk(%{pending: [head | tail]} = state) do
    {[head], %{state | pending: tail}}
  end

  defp next_chunk(%{done?: true} = state) do
    {:halt, state}
  end

  defp next_chunk(state) do
    receive do
      {:http, {request_id, :stream, chunk}} when request_id == state.request_id ->
        {events, buffer} = decode_chunk(state.buffer, chunk, state.parser)
        :ok = :httpc.stream_next(state.stream_pid)

        case events do
          [] -> next_chunk(%{state | buffer: buffer})
          [head | tail] -> {[head], %{state | buffer: buffer, pending: tail}}
        end

      {:http, {request_id, :stream_end, _headers}} when request_id == state.request_id ->
        {events, buffer} = decode_tail(state.buffer, state.parser)
        state = %{state | buffer: buffer, done?: true}

        case events do
          [] -> {:halt, state}
          [head | tail] -> {[head], %{state | pending: tail}}
        end

      {:http, {request_id, {:error, reason}}} when request_id == state.request_id ->
        raise "NDJSON stream failed: #{inspect(reason)}"
    after
      state.chunk_timeout ->
        raise Sprites.Error.TimeoutError, timeout: state.chunk_timeout
    end
  end

  defp cleanup(%{done?: true}), do: :ok

  defp cleanup(state) do
    :httpc.cancel_request(state.request_id)
    :ok
  end

  defp parse_non_stream_body(body, parser) do
    body = IO.iodata_to_binary(body)

    cond do
      body == "" ->
        []

      true ->
        case Jason.decode(body) do
          {:ok, list} when is_list(list) ->
            Enum.map(list, &apply_parser(&1, parser))

          {:ok, map} when is_map(map) ->
            [apply_parser(map, parser)]

          {:error, _} ->
            {events, _tail} = decode_tail(body, parser)
            events
        end
    end
  end

  defp decode_tail(buffer, parser) do
    decode_chunk(buffer <> "\n", "", parser)
  end

  defp decode_chunk(buffer, chunk, parser) do
    full = buffer <> IO.iodata_to_binary(chunk)
    parts = String.split(full, "\n")

    {complete, tail} =
      case List.last(parts) do
        "" ->
          {Enum.drop(parts, -1), ""}

        incomplete ->
          {Enum.drop(parts, -1), incomplete}
      end

    events =
      complete
      |> Enum.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn line ->
        case Jason.decode(line) do
          {:ok, %{} = event} ->
            apply_parser(event, parser)

          {:ok, event} ->
            %{"type" => "error", "message" => "expected JSON object", "raw" => event}

          {:error, reason} ->
            %{
              "type" => "error",
              "message" => "invalid ndjson line",
              "raw" => line,
              "reason" => inspect(reason)
            }
        end
      end)

    {events, tail}
  end

  defp build_request(client, method, path, params, extra_headers, opts) do
    url = build_url(client, path, params)

    headers =
      [{"authorization", "Bearer #{client.token}"} | extra_headers]
      |> maybe_add_content_type(opts)

    charlist_headers =
      Enum.map(headers, fn {k, v} ->
        {to_charlist(to_string(k)), to_charlist(to_string(v))}
      end)

    request =
      case method do
        :post ->
          body = request_body(opts)
          content_type = header_value(headers, "content-type") || "application/json"
          {to_charlist(url), charlist_headers, to_charlist(content_type), body}

        :put ->
          body = request_body(opts)
          content_type = header_value(headers, "content-type") || "application/json"
          {to_charlist(url), charlist_headers, to_charlist(content_type), body}

        _ ->
          {to_charlist(url), charlist_headers}
      end

    {request, charlist_headers}
  end

  defp request_body(opts) do
    cond do
      Keyword.has_key?(opts, :json) ->
        Jason.encode!(Keyword.fetch!(opts, :json))

      Keyword.has_key?(opts, :body) ->
        Keyword.fetch!(opts, :body) |> IO.iodata_to_binary()

      true ->
        ""
    end
  end

  defp maybe_add_content_type(headers, opts) do
    if Keyword.has_key?(opts, :json) do
      if header_value(headers, "content-type") do
        headers
      else
        [{"content-type", "application/json"} | headers]
      end
    else
      headers
    end
  end

  defp header_value(headers, key) do
    key = String.downcase(key)

    headers
    |> Enum.find_value(fn {k, v} ->
      if String.downcase(to_string(k)) == key do
        to_string(v)
      else
        nil
      end
    end)
  end

  defp build_url(%Client{base_url: base_url}, path, params) do
    base = String.trim_trailing(base_url, "/")

    query =
      case params do
        [] -> nil
        %{} = map -> URI.encode_query(map)
        list when is_list(list) -> URI.encode_query(list)
      end

    if query in [nil, ""] do
      "#{base}#{path}"
    else
      "#{base}#{path}?#{query}"
    end
  end

  defp apply_parser(%{} = event, parser) do
    case parser.(event) do
      {:ok, parsed} -> parsed
      {:error, reason} -> %{"type" => "error", "message" => inspect(reason), "raw" => event}
      parsed -> parsed
    end
  rescue
    exception ->
      %{"type" => "error", "message" => Exception.message(exception), "raw" => event}
  end
end
