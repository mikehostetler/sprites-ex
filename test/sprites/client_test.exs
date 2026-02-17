defmodule Sprites.ClientTest do
  use ExUnit.Case, async: true

  alias Sprites.Client

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

  test "list_sprites_page normalizes legacy array response" do
    fake = fn request ->
      response = %Req.Response{status: 200, body: [%{"name" => "demo"}], headers: []}
      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, page} = Client.list_sprites_page(client)
    assert page["sprites"] == [%{"name" => "demo"}]
    assert page["has_more"] == false
    assert page["next_continuation_token"] == nil
  end

  test "list_sprites_page forwards pagination params" do
    parent = self()

    fake = fn request ->
      send(parent, {:request, request})

      response =
        %Req.Response{
          status: 200,
          body: %{"sprites" => [], "has_more" => true, "next_continuation_token" => "tok"},
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, %{"has_more" => true, "next_continuation_token" => "tok"}} =
             Client.list_sprites_page(client,
               prefix: "dev-",
               max_results: 10,
               continuation_token: "abc"
             )

    assert_receive {:request, request}
    assert request.method == :get
    assert request.url.path == "/v1/sprites"

    decoded = request.url.query |> URI.query_decoder() |> Enum.to_list()
    assert {"prefix", "dev-"} in decoded
    assert {"max_results", "10"} in decoded
    assert {"continuation_token", "abc"} in decoded
  end

  test "exec_http builds cmd/env query and forwards stdin body" do
    parent = self()

    fake = fn request ->
      send(parent, {:request, request})

      response =
        %Req.Response{
          status: 200,
          body: %{"exit_code" => 0, "stdout" => "ok\n", "unknown" => "kept"},
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, body} =
             Client.exec_http(
               client,
               "my-sprite",
               "python",
               ["-c", "print(1)"],
               stdin: true,
               stdin_data: "echo hi\n",
               env: [{"FOO", "bar"}],
               dir: "/app"
             )

    assert body["exit_code"] == 0
    assert body["stdout"] == "ok\n"
    assert body["unknown"] == "kept"

    assert_receive {:request, request}
    assert request.method == :post
    assert request.url.path == "/v1/sprites/my-sprite/exec"
    assert request.body == "echo hi\n"

    decoded = request.url.query |> URI.query_decoder() |> Enum.to_list()
    assert {"cmd", "python"} in decoded
    assert {"cmd", "-c"} in decoded
    assert {"cmd", "print(1)"} in decoded
    assert {"stdin", "true"} in decoded
    assert {"env", "FOO=bar"} in decoded
    assert {"dir", "/app"} in decoded
  end

  test "create_sprite returns sprite struct with parsed attrs" do
    parent = self()

    fake = fn request ->
      send(parent, {:request, request})

      response =
        %Req.Response{
          status: 201,
          body: %{
            "id" => "sprite-1",
            "name" => "demo",
            "status" => "running",
            "url_settings" => %{"auth" => "sprite"}
          },
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, sprite} = Client.create_sprite(client, "demo", url_settings: %{auth: "sprite"})
    assert sprite.name == "demo"
    assert sprite.id == "sprite-1"
    assert sprite.status == "running"
    assert sprite.raw["url_settings"]["auth"] == "sprite"

    assert_receive {:request, request}
    assert request.method == :post
    assert request.url.path == "/v1/sprites"
  end
end
