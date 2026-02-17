defmodule Sprites.ServiceTest do
  use ExUnit.Case, async: true

  alias Sprites.{Client, Service, StreamMessage}
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

  test "list_by_name parses services list" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: [
            %{
              "name" => "web",
              "cmd" => "python",
              "args" => ["-m", "http.server", "8000"],
              "needs" => ["db"],
              "http_port" => 8000,
              "state" => %{"status" => "running", "pid" => 1234}
            }
          ],
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, [service]} = Service.list_by_name(client, "demo")
    assert service.name == "web"
    assert service.cmd == "python"
    assert service.state.status == "running"
    assert service.state.pid == 1234
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
             Service.list_by_name(client, "demo")
  end

  test "list_by_name returns shape error when list contains non-map entries" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: [%{"name" => "web", "cmd" => "python"}, "bad"],
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:error, {:unexpected_response_shape, [%{"name" => "web", "cmd" => "python"}, "bad"]}} =
             Service.list_by_name(client, "demo")
  end

  test "upsert_by_name forwards duration only when provided" do
    parent = self()

    fake = fn request ->
      send(parent, {:request, request})

      response =
        %Req.Response{
          status: 200,
          body: %{"name" => "web", "cmd" => "python", "args" => [], "needs" => []},
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, %Service{name: "web"}} =
             Service.upsert_by_name(
               client,
               "demo",
               "web",
               %{"cmd" => "python", "args" => [], "needs" => []},
               duration: "5s"
             )

    assert_receive {:request, request}
    assert request.url.path == "/v1/sprites/demo/services/web"
    assert request.url.query == "duration=5s"

    body = request.body |> IO.iodata_to_binary() |> Jason.decode!()
    assert body["name"] == "web"
    assert body["cmd"] == "python"
  end

  test "get_by_name returns shape error for unexpected payload" do
    fake = fn request ->
      response = %Req.Response{status: 200, body: ["unexpected"], headers: []}
      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:error, {:unexpected_response_shape, ["unexpected"]}} =
             Service.get_by_name(client, "demo", "web")
  end

  test "logs_by_name streams typed events" do
    {:ok, server} =
      TestHTTPServer.start_once(fn socket, _request ->
        chunks = [
          ~s({"type":"stdout","data":"hello\\n","timestamp":1}\n),
          ~s({"type":"complete","timestamp":2,"log_files":{"stdout":"/.sprite/logs/services/web.log"}}\n)
        ]

        :ok = TestHTTPServer.send_chunked(socket, "application/x-ndjson", chunks)
      end)

    client = Client.new("token", base_url: "http://127.0.0.1:#{server.port}")

    assert {:ok, stream} = Service.logs_by_name(client, "demo", "web", lines: 100, duration: "0")

    assert [
             %StreamMessage{type: "stdout", data: "hello\n", timestamp: 1},
             %StreamMessage{
               type: "complete",
               timestamp: 2,
               log_files: %{"stdout" => "/.sprite/logs/services/web.log"}
             }
           ] = Enum.to_list(stream)
  end
end
