defmodule Sprites.CheckpointTest do
  use ExUnit.Case, async: true

  alias Sprites.{Checkpoint, Client, StreamMessage}
  alias Sprites.TestHTTPServer

  defp client_with_adapter(adapter) do
    token = "test-token"
    base_url = "https://api.sprites.dev"

    client = Client.new(token, base_url: base_url)

    req =
      Req.new(
        base_url: base_url,
        headers: [{"authorization", "Bearer #{token}"}],
        adapter: adapter
      )

    %{client | req: req}
  end

  test "list_by_name parses checkpoint list" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: [
            %{
              "id" => "v1",
              "create_time" => "2026-01-01T00:00:00Z",
              "history" => [],
              "comment" => "init"
            }
          ],
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, [checkpoint]} = Checkpoint.list_by_name(client, "demo")
    assert checkpoint.id == "v1"
    assert checkpoint.comment == "init"
    assert %DateTime{} = checkpoint.create_time
  end

  test "create_by_name streams typed checkpoint messages" do
    {:ok, server} =
      TestHTTPServer.start_once(fn socket, _request ->
        chunks = [
          ~s({"type":"info","data":"creating","time":"2026-01-12T21:42:34.915667102Z"}\n),
          ~s({"type":"complete","data":"done"}\n)
        ]

        :ok = TestHTTPServer.send_chunked(socket, "application/x-ndjson", chunks)
      end)

    client = Client.new("token", base_url: "http://127.0.0.1:#{server.port}")

    assert {:ok, stream} = Checkpoint.create_by_name(client, "demo", comment: "before")

    assert [
             %StreamMessage{
               type: "info",
               data: "creating",
               time: "2026-01-12T21:42:34.915667102Z"
             },
             %StreamMessage{type: "complete", data: "done"}
           ] = Enum.to_list(stream)
  end
end
