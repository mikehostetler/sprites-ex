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

  test "parse_api_error_body validates typed error payload fields" do
    input = %{
      "error" => "concurrent_sprite_limit_exceeded",
      "message" => "Too many concurrent sprites",
      "limit" => 5,
      "current_count" => 5,
      "upgrade_available" => true
    }

    assert {:ok, parsed} = Shapes.parse_api_error_body(input)
    assert parsed["error"] == "concurrent_sprite_limit_exceeded"
    assert parsed["limit"] == 5
  end

  test "parse_stream_message validates normalized stream messages" do
    input = %{
      "type" => "complete",
      "message" => "done",
      "exit_code" => 0,
      "timestamp" => 1_767_609_000_000,
      "log_files" => %{"stdout" => "/tmp/stdout.log"}
    }

    assert {:ok, parsed} = Shapes.parse_stream_message(input)
    assert parsed["type"] == "complete"
    assert parsed["log_files"]["stdout"] == "/tmp/stdout.log"
  end
end
