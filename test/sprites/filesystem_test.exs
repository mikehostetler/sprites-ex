defmodule Sprites.FilesystemTest do
  use ExUnit.Case, async: true

  alias Sprites.{Client, Filesystem, Sprite}
  alias Sprites.Error.APIError

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

  defp filesystem_with_adapter(adapter, working_dir \\ "/app") do
    client = client_with_adapter(adapter)
    sprite = Sprite.new(client, "demo")
    Filesystem.new(sprite, working_dir)
  end

  test "read returns APIError on non-404 failures" do
    fake = fn request ->
      response =
        %Req.Response{
          status: 500,
          body: %{"error" => "read_failed", "message" => "read failure"},
          headers: []
        }

      {request, response}
    end

    fs = filesystem_with_adapter(fake)

    assert {:error, %APIError{} = err} = Filesystem.read(fs, "file.txt")
    assert err.status == 500
    assert err.error_code == "read_failed"
  end

  test "mkdir_p reports cleanup delete failures" do
    parent = self()
    {:ok, counter} = Agent.start(fn -> 0 end)

    on_exit(fn ->
      if Process.alive?(counter) do
        Agent.stop(counter)
      end
    end)

    fake = fn request ->
      send(parent, {:request, request})

      call_idx =
        Agent.get_and_update(counter, fn current ->
          {current, current + 1}
        end)

      response =
        case call_idx do
          0 ->
            %Req.Response{status: 200, body: "", headers: []}

          _ ->
            %Req.Response{
              status: 500,
              body: %{"error" => "delete_failed", "message" => "cleanup failed"},
              headers: []
            }
        end

      {request, response}
    end

    fs = filesystem_with_adapter(fake)

    assert {:error, %APIError{} = err} = Filesystem.mkdir_p(fs, "deep/nested/path")
    assert err.status == 500
    assert err.error_code == "delete_failed"

    assert_receive {:request, req1}
    assert_receive {:request, req2}
    assert req1.url.path == "/v1/sprites/demo/fs/write"
    assert req2.url.path == "/v1/sprites/demo/fs/delete"
  end
end
