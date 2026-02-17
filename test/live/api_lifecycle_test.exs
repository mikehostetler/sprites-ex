defmodule Sprites.Live.APILifecycleTest do
  use Sprites.LiveCase, async: false

  @moduletag :integration
  @moduletag :live
  @moduletag skip:
               if(Sprites.LiveCase.live_token() in [nil, ""],
                 do: "SPRITES_TEST_TOKEN not set",
                 else: false
               )

  test "exec http and kill active session", context do
    token = context[:token]
    base_url = context[:base_url]
    client = client!(token, base_url)
    name = unique_sprite_name("sprites-ex-live-exec")

    try do
      assert {:ok, sprite} = create_sprite(client, name)

      assert {:ok, http_result} =
               Sprites.exec_http(sprite, "sh", ["-lc", "echo sprites-ex-live-exec"])

      assert_exec_http_contains(http_result, "sprites-ex-live-exec")

      assert {:ok, command} = Sprites.spawn(sprite, "sh", ["-lc", "sleep 120"])
      assert {:ok, session} = wait_for_active_session(sprite, 20_000)

      assert {:ok, kill_stream} =
               Sprites.kill_session(sprite, session.id, signal: "SIGTERM", timeout: "10s")

      kill_events = Enum.to_list(kill_stream)
      assert kill_events != []

      assert Enum.any?(kill_events, fn event ->
               event.type in ["signal", "killed", "exited", "complete", "timeout", "error"]
             end)

      await_result = Sprites.await(command, 30_000)

      assert match?({:ok, code} when is_integer(code), await_result) or
               await_result in [{:error, :closed}, {:error, {:ws_closed, 1001, "stream closed"}}]

      assert :ok = wait_for_session_exit(sprite, session.id, 20_000)
    after
      _ = Sprites.destroy(Sprites.sprite(client, name))
    end
  end

  test "checkpoint lifecycle create list get restore", context do
    token = context[:token]
    base_url = context[:base_url]
    client = client!(token, base_url)
    name = unique_sprite_name("sprites-ex-live-checkpoint")

    try do
      assert {:ok, sprite} = create_sprite(client, name)

      assert {:ok, _checkpoint_cmd} = Sprites.spawn(sprite, "sh", ["-lc", "sleep 120"])
      assert {:ok, _session} = wait_for_active_session(sprite, 20_000)

      assert {:ok, create_stream} =
               Sprites.create_checkpoint(sprite, comment: "sprites-ex live checkpoint")

      create_events = Enum.to_list(create_stream)
      assert create_events != []
      assert Enum.any?(create_events, &(&1.type in ["info", "complete"]))

      assert {:ok, checkpoints} = wait_for_checkpoints(sprite, 20_000)
      checkpoint = hd(checkpoints)

      assert is_binary(checkpoint.id)
      assert {:ok, fetched} = Sprites.get_checkpoint(sprite, checkpoint.id)
      assert is_binary(fetched.id)
      assert fetched.id != ""

      assert {:ok, restore_stream} = Sprites.restore_checkpoint(sprite, fetched.id)
      restore_events = Enum.to_list(restore_stream)
      assert restore_events != []
      assert Enum.any?(restore_events, &(&1.type in ["info", "complete"]))
    after
      _ = Sprites.destroy(Sprites.sprite(client, name))
    end
  end

  defp wait_for_active_session(sprite, timeout_ms) do
    wait_until(timeout_ms, 250, fn ->
      case Sprites.list_sessions(sprite) do
        {:ok, [session | _]} -> {:ok, session}
        {:ok, []} -> :retry
        {:error, _reason} -> :retry
      end
    end)
  end

  defp wait_for_checkpoints(sprite, timeout_ms) do
    wait_until(timeout_ms, 250, fn ->
      case Sprites.list_checkpoints(sprite) do
        {:ok, [_ | _] = checkpoints} -> {:ok, checkpoints}
        {:ok, []} -> :retry
        {:error, _reason} -> :retry
      end
    end)
  end

  defp wait_for_session_exit(sprite, session_id, timeout_ms) do
    case wait_until(timeout_ms, 250, fn ->
           case Sprites.list_sessions(sprite) do
             {:ok, sessions} ->
               if Enum.any?(sessions, &(to_string(&1.id) == to_string(session_id))) do
                 :retry
               else
                 {:ok, :done}
               end

             {:error, _reason} ->
               :retry
           end
         end) do
      {:ok, :done} -> :ok
      {:error, reason} -> {:error, reason}
    end
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

  defp assert_exec_http_contains(result, expected_substring) when is_map(result) do
    stdout = result["stdout"] || result["output"] || ""
    assert is_binary(stdout)
    assert String.contains?(stdout, expected_substring)
  end

  defp assert_exec_http_contains(result, expected_substring) when is_binary(result) do
    assert :binary.match(result, expected_substring) != :nomatch
  end
end
