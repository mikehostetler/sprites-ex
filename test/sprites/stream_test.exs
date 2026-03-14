defmodule Sprites.StreamTest do
  use ExUnit.Case, async: false

  alias Sprites.{Client, Sprite}
  alias Sprites.Stream, as: SpritesStream

  setup do
    previous = Application.get_env(:sprites, :command_module)
    Application.put_env(:sprites, :command_module, Sprites.FakeCommand)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:sprites, :command_module)
        module -> Application.put_env(:sprites, :command_module, module)
      end
    end)

    :ok
  end

  defp sprite do
    client = Client.new("token", base_url: "https://api.sprites.dev")
    Sprite.new(client, "demo")
  end

  test "emits stdout chunks and ignores stderr" do
    output =
      SpritesStream.new(sprite(), "echo", ["hi"],
        test_events: [{:stdout, "a"}, {:stderr, "ignored"}, {:stdout, "b"}, {:exit, 0}]
      )
      |> Enum.to_list()

    assert output == ["a", "b"]
  end

  test "stops command when consumer halts early" do
    result =
      SpritesStream.new(sprite(), "tail", ["-f", "/tmp/app.log"],
        test_events: [{:stdout, "line1\n"}]
      )
      |> Stream.take(1)
      |> Enum.to_list()

    assert result == ["line1\n"]
    assert_receive {:fake_command_stop, _ref}
  end

  test "idle_timeout halts stream and stops running command" do
    result =
      SpritesStream.new(sprite(), "sleep", ["10"], idle_timeout: 5, test_events: [])
      |> Enum.to_list()

    assert result == []
    assert_receive {:fake_command_stop, _ref}
  end

  test "stops command on stream error event before raising" do
    assert_raise RuntimeError, ~r/Stream error/, fn ->
      SpritesStream.new(sprite(), "bash", ["-lc", "exit 1"], test_events: [{:error, :boom}])
      |> Enum.to_list()
    end

    assert_receive {:fake_command_stop, _ref}
  end
end
