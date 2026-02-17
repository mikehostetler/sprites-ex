defmodule Sprites.Live.SmokeTest do
  use Sprites.LiveCase, async: false

  @moduletag :integration
  @moduletag :live
  @moduletag skip:
               if(System.get_env("SPRITES_TEST_TOKEN") in [nil, ""],
                 do: "SPRITES_TEST_TOKEN not set",
                 else: false
               )

  test "sprite lifecycle smoke", context do
    token = context[:token]
    base_url = context[:base_url]
    client = client!(token, base_url)
    name = unique_sprite_name("sprites-ex-live")

    try do
      assert {:ok, sprite} = Sprites.create(client, name)
      assert sprite.name == name

      assert {:ok, info} = Sprites.get_sprite(client, name)
      assert info["name"] == name

      assert {:ok, page} = Sprites.list_page(client, prefix: name, max_results: 5)
      assert is_list(page["sprites"])

      assert :ok = Sprites.update_url_settings(sprite, %{auth: "sprite"})
    after
      _ = Sprites.destroy(Sprites.sprite(client, name))
    end
  end
end
