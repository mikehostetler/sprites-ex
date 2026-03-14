defmodule Sprites.NDJSONStreamTest do
  use ExUnit.Case, async: true

  alias Sprites.{Client, NDJSONStream}
  alias Sprites.Error.APIError
  alias Sprites.TestHTTPServer

  test "request parses chunked NDJSON across chunk boundaries" do
    {:ok, server} =
      TestHTTPServer.start_once(fn socket, _request ->
        chunks = [
          ~s({"type":"info","data":"one"}\n{"type":"info","da),
          ~s(ta":"two"}\n{"type":"complete","data":"done"}\n)
        ]

        :ok = TestHTTPServer.send_chunked(socket, "application/x-ndjson", chunks)
      end)

    client = Client.new("token", base_url: "http://127.0.0.1:#{server.port}")

    assert {:ok, stream} = NDJSONStream.request(client, :get, "/stream", parser: & &1)

    assert [
             %{"type" => "info", "data" => "one"},
             %{"type" => "info", "data" => "two"},
             %{"type" => "complete", "data" => "done"}
           ] = Enum.to_list(stream)
  end

  test "request maps non-2xx into APIError" do
    {:ok, server} =
      TestHTTPServer.start_once(fn socket, _request ->
        :ok =
          TestHTTPServer.send_json(socket, 404, %{"error" => "not_found", "message" => "missing"})
      end)

    client = Client.new("token", base_url: "http://127.0.0.1:#{server.port}")

    assert {:error, %APIError{} = err} =
             NDJSONStream.request(client, :get, "/missing", parser: & &1)

    assert err.status == 404
    assert err.error_code == "not_found"
  end

  test "request emits structured error events for invalid ndjson lines" do
    {:ok, server} =
      TestHTTPServer.start_once(fn socket, _request ->
        chunks = [
          "not-json\n",
          ~s({"type":"complete"}\n)
        ]

        :ok = TestHTTPServer.send_chunked(socket, "application/x-ndjson", chunks)
      end)

    client = Client.new("token", base_url: "http://127.0.0.1:#{server.port}")

    assert {:ok, stream} = NDJSONStream.request(client, :get, "/stream", parser: & &1)

    assert [
             %{"type" => "error", "message" => "invalid ndjson line"},
             %{"type" => "complete"}
           ] =
             Enum.to_list(stream)
             |> Enum.map(fn event ->
               Map.take(event, ["type", "message"])
             end)
  end

  test "request returns explicit status tuple when parser yields nil error payload" do
    {:ok, server} =
      TestHTTPServer.start_once(fn socket, _request ->
        :ok = TestHTTPServer.send_text(socket, 304, "not modified")
      end)

    client = Client.new("token", base_url: "http://127.0.0.1:#{server.port}")

    assert {:error, {:http_status, 304, body}} =
             NDJSONStream.request(client, :get, "/cached", parser: & &1)

    assert body in ["", "not modified"]
  end
end
