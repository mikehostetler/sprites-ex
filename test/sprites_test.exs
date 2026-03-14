defmodule SpritesTest do
  use ExUnit.Case
  doctest Sprites

  test "client constructor returns a client" do
    client = Sprites.new("test-token")
    assert %Sprites.Client{} = client
    assert client.token == "test-token"
  end
end
