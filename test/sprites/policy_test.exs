defmodule Sprites.PolicyTest do
  use ExUnit.Case, async: true

  alias Sprites.{Client, Policy}
  alias Sprites.Policy.Rule

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

  test "get_by_name parses network policy" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 200,
          body: %{"rules" => [%{"domain" => "example.com", "action" => "allow"}]},
          headers: []
        }

      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:ok, %Policy{rules: [%Rule{domain: "example.com", action: "allow"}]}} =
             Policy.get_by_name(client, "demo")
  end

  test "get_by_name returns shape error for unexpected payload" do
    fake = fn request ->
      response = %Req.Response{status: 200, body: ["unexpected"], headers: []}
      {request, response}
    end

    client = client_with_adapter(fake)

    assert {:error, {:unexpected_response_shape, ["unexpected"]}} =
             Policy.get_by_name(client, "demo")
  end

  test "update_by_name posts policy payload" do
    parent = self()

    fake = fn request ->
      send(parent, {:request, request})
      {request, %Req.Response{status: 200, body: %{}, headers: []}}
    end

    client = client_with_adapter(fake)

    policy = %Policy{
      rules: [
        %Rule{domain: "example.com", action: "allow"},
        %Rule{domain: "blocked.example.com", action: "deny", include: "*.blocked.example.com"}
      ]
    }

    assert :ok = Policy.update_by_name(client, "demo", policy)

    assert_receive {:request, request}
    assert request.method == :post
    assert request.url.path == "/v1/sprites/demo/policy/network"

    body = request.body |> IO.iodata_to_binary() |> Jason.decode!()
    assert body["rules"] |> Enum.map(& &1["domain"]) == ["example.com", "blocked.example.com"]
  end
end
