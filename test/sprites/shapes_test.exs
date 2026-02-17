defmodule Sprites.ShapesTest do
  use ExUnit.Case, async: true

  alias Sprites.Shapes

  test "parse_sprite preserves unknown fields" do
    input = %{
      "id" => "sprite-1",
      "name" => "demo",
      "status" => "running",
      "future_field" => "kept"
    }

    assert {:ok, parsed} = Shapes.parse_sprite(input)
    assert parsed["future_field"] == "kept"
  end

  test "parse_sprite_page validates required sprites list" do
    assert {:error, {:shape_error, :sprite_page, _errors}} = Shapes.parse_sprite_page(%{})
  end

  test "parse_session rejects missing required fields" do
    assert {:error, {:shape_error, :session, _errors}} = Shapes.parse_session(%{"id" => 12})
  end

  test "parse_service_log_event parses complete event" do
    event = %{
      "type" => "complete",
      "timestamp" => 1_767_609_000_000,
      "log_files" => %{"stdout" => "/.sprite/logs/services/web.log"}
    }

    assert {:ok, parsed} = Shapes.parse_service_log_event(event)
    assert parsed["type"] == "complete"
    assert parsed["log_files"]["stdout"] == "/.sprite/logs/services/web.log"
  end

  test "parse_exec_kill_event parses complete event" do
    event = %{"type" => "complete", "exit_code" => 143}

    assert {:ok, parsed} = Shapes.parse_exec_kill_event(event)
    assert parsed["exit_code"] == 143
  end
end
