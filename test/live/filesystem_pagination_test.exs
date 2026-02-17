defmodule Sprites.Live.FilesystemPaginationTest do
  use Sprites.LiveCase, async: false

  alias Sprites.Filesystem

  @moduletag :integration
  @moduletag :live
  @moduletag skip:
               if(Sprites.LiveCase.live_token() in [nil, ""],
                 do: "SPRITES_TEST_TOKEN not set",
                 else: false
               )

  test "filesystem write/read/stat/remove round-trip", context do
    token = context[:token]
    base_url = context[:base_url]
    client = client!(token, base_url)
    name = unique_sprite_name("sprites-ex-live-fs")
    dir_name = "tmp/sprites-ex-live-#{System.unique_integer([:positive, :monotonic])}"
    file_name = "#{dir_name}/hello.txt"
    content = "sprites-live-filesystem\n"

    try do
      assert {:ok, sprite} = create_sprite(client, name)
      fs = Sprites.filesystem(sprite, "/")

      assert :ok = Filesystem.mkdir_p(fs, dir_name)
      assert :ok = Filesystem.write(fs, file_name, content)
      assert {:ok, ^content} = Filesystem.read(fs, file_name)

      assert {:ok, stat} = Filesystem.stat(fs, file_name)
      assert is_map(stat)
      assert stat["name"] == "hello.txt"

      assert {:ok, entries} = Filesystem.ls(fs, dir_name)
      assert Enum.any?(entries, &(&1["name"] == "hello.txt"))

      assert :ok = Filesystem.rm(fs, file_name)
      assert {:error, :enoent} = Filesystem.read(fs, file_name)

      assert :ok = Filesystem.rm_rf(fs, dir_name)
    after
      _ = Sprites.destroy(Sprites.sprite(client, name))
    end
  end

  test "paged list supports multiple created sprites", context do
    token = context[:token]
    base_url = context[:base_url]
    client = client!(token, base_url)
    prefix = unique_sprite_name("sprites-ex-live-page")
    name_a = "#{prefix}-a"
    name_b = "#{prefix}-b"

    try do
      assert {:ok, _sprite_a} = create_sprite(client, name_a)
      assert {:ok, _sprite_b} = create_sprite(client, name_b)

      assert {:ok, seen_names} = wait_for_list_contains(client, prefix, [name_a, name_b], 20_000)
      assert MapSet.member?(seen_names, name_a)
      assert MapSet.member?(seen_names, name_b)

      assert {:ok, page_1} = Sprites.list_page(client, prefix: prefix, max_results: 1)
      page_1_names = page_names(page_1)
      assert page_1_names != []

      case {page_1["has_more"], page_1["next_continuation_token"]} do
        {true, token} when is_binary(token) and token != "" ->
          assert {:ok, page_2} =
                   Sprites.list_page(client,
                     prefix: prefix,
                     max_results: 1,
                     continuation_token: token
                   )

          combined_names = MapSet.new(page_1_names ++ page_names(page_2))
          assert MapSet.member?(combined_names, name_a)
          assert MapSet.member?(combined_names, name_b)

        _ ->
          combined_names = MapSet.new(page_1_names)
          assert MapSet.member?(combined_names, name_a)
          assert MapSet.member?(combined_names, name_b)
      end
    after
      _ = Sprites.destroy(Sprites.sprite(client, name_a))
      _ = Sprites.destroy(Sprites.sprite(client, name_b))
    end
  end

  defp page_names(%{"sprites" => sprites}) when is_list(sprites) do
    sprites
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.filter(&is_binary/1)
  end

  defp page_names(_), do: []

  defp wait_for_list_contains(client, prefix, expected_names, timeout_ms) do
    wait_until(timeout_ms, 250, fn ->
      case Sprites.list_page(client, prefix: prefix, max_results: 50) do
        {:ok, page} ->
          names = MapSet.new(page_names(page))

          if Enum.all?(expected_names, &MapSet.member?(names, &1)) do
            {:ok, names}
          else
            :retry
          end

        {:error, _reason} ->
          :retry
      end
    end)
  end

  defp wait_until(timeout_ms, interval_ms, fun) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(deadline, interval_ms, fun)
  end

  defp do_wait_until(deadline, interval_ms, fun) do
    case fun.() do
      {:ok, _value} = ok ->
        ok

      :retry ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(interval_ms)
          do_wait_until(deadline, interval_ms, fun)
        else
          {:error, :timeout}
        end

      unexpected ->
        {:error, {:unexpected_poll_result, unexpected}}
    end
  end
end
