defmodule Sprites.SessionTest do
  use ExUnit.Case, async: true

  alias Sprites.{Client, Session, StreamMessage}
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

  test "list_by_name parses envelope response" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: %{"sessions" => [%{"id" => 7, "command" => "sleep", "is_active" => true}]},
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, [%Session{id: 7, command: "sleep", is_active: true}]} =
             Session.list_by_name(client, "demo")
  end

  test "list_by_name parses array response" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: [%{"id" => "2", "command" => "bash", "is_active" => false}],
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, [%Session{id: "2", command: "bash", is_active: false}]} =
             Session.list_by_name(client, "demo")
  end

  test "list_by_name returns shape error for unexpected payload" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: %{"unexpected" => true},
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:error, {:unexpected_response_shape, %{"unexpected" => true}}} =
             Session.list_by_name(client, "demo")
  end

  test "list_by_name returns shape error when list contains non-map entries" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: [%{"id" => 1, "command" => "ls"}, "bad"],
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:error, {:unexpected_response_shape, [%{"id" => 1, "command" => "ls"}, "bad"]}} =
             Session.list_by_name(client, "demo")
  end

  test "kill_by_name streams kill events" do
    parent = self()

    {:ok, server} =
      TestHTTPServer.start_once(fn socket, request ->
        send(parent, {:request, request})

        chunks = [
          ~s({"type":"signal","message":"sent","signal":"SIGTERM","pid":123}\n{"type":"complete"),
          ~s(,"exit_code":143}\n)
        ]

        :ok = TestHTTPServer.send_chunked(socket, "application/x-ndjson", chunks)
      end)

    client = Client.new("token", base_url: "http://127.0.0.1:#{server.port}")

    assert {:ok, stream} =
             Session.kill_by_name(client, "demo", 123, signal: "SIGTERM", timeout: "5s")

    assert [
             %StreamMessage{type: "signal", signal: "SIGTERM", pid: 123},
             %StreamMessage{type: "complete", exit_code: 143}
           ] = Enum.to_list(stream)

    assert_receive {:request, request}
    assert request =~ "POST /v1/sprites/demo/exec/123/kill?"
    assert request =~ "signal=SIGTERM"
    assert request =~ "timeout=5s"
  end
end
