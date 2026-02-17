defmodule Sprites.Live.ServicesPolicyTest do
  use Sprites.LiveCase, async: false

  alias Sprites.Error.APIError
  alias Sprites.Policy
  alias Sprites.Policy.Rule

  @moduletag :integration
  @moduletag :live
  @moduletag skip:
               if(Sprites.LiveCase.live_token() in [nil, ""],
                 do: "SPRITES_TEST_TOKEN not set",
                 else: false
               )

  test "network policy round-trip", context do
    token = context[:token]
    base_url = context[:base_url]
    client = client!(token, base_url)
    name = unique_sprite_name("sprites-ex-live-policy")

    try do
      assert {:ok, sprite} = create_sprite(client, name)

      policy = %Policy{
        rules: [
          %Rule{domain: "example.com", action: "allow"},
          %Rule{domain: "blocked.example.com", action: "deny"}
        ]
      }

      assert :ok = Sprites.update_network_policy(sprite, policy)

      assert {:ok, fetched} =
               wait_for_policy_rules(sprite, ["example.com", "blocked.example.com"], 15_000)

      assert Enum.any?(fetched.rules, fn rule ->
               rule.domain == "example.com" and rule.action == "allow"
             end)

      assert Enum.any?(fetched.rules, fn rule ->
               rule.domain == "blocked.example.com" and rule.action == "deny"
             end)
    after
      _ = Sprites.destroy(Sprites.sprite(client, name))
    end
  end

  test "services API smoke", context do
    token = context[:token]
    base_url = context[:base_url]
    client = client!(token, base_url)
    name = unique_sprite_name("sprites-ex-live-service")
    service_name = "live-web"

    try do
      assert {:ok, sprite} = create_sprite(client, name)

      attrs = %{
        cmd: "sh",
        args: ["-lc", "while true; do echo sprites-service-live; sleep 1; done"],
        needs: []
      }

      assert {:ok, initial_services} = Sprites.list_services(sprite)
      assert is_list(initial_services)

      case Sprites.upsert_service(sprite, service_name, attrs) do
        {:ok, upserted} ->
          assert upserted.cmd in ["sh", nil]

          assert {:ok, listed} = wait_for_service(sprite, service_name, 15_000)
          assert Enum.any?(listed, &(&1.name == service_name))

          assert {:ok, fetched} = Sprites.get_service(sprite, service_name)
          assert fetched.cmd in ["sh", nil]

          assert {:ok, start_stream} = Sprites.start_service(sprite, service_name, duration: "3s")
          start_events = Enum.to_list(start_stream)
          assert start_events != []

          assert {:ok, logs_stream} =
                   Sprites.service_logs(sprite, service_name, lines: 50, duration: "2s")

          logs_events = Enum.to_list(logs_stream)
          assert logs_events != []

          assert Enum.any?(logs_events, fn event ->
                   data = event.data || event.message || ""

                   event.type in ["stdout", "stderr", "info", "complete"] and
                     (data == "" or String.contains?(data, "sprites-service-live"))
                 end)

          assert {:ok, stop_stream} = Sprites.stop_service(sprite, service_name, timeout: "10s")
          stop_events = Enum.to_list(stop_stream)
          assert stop_events != []

        {:error, %APIError{status: 400, message: message}} ->
          assert String.contains?(String.downcase(message), "service name required")
      end
    after
      _ = Sprites.destroy(Sprites.sprite(client, name))
    end
  end

  defp wait_for_policy_rules(sprite, domains, timeout_ms) do
    wait_until(timeout_ms, 250, fn ->
      case Sprites.get_network_policy(sprite) do
        {:ok, policy} ->
          existing_domains = MapSet.new(Enum.map(policy.rules, & &1.domain))

          if Enum.all?(domains, &MapSet.member?(existing_domains, &1)) do
            {:ok, policy}
          else
            :retry
          end

        {:error, _reason} ->
          :retry
      end
    end)
  end

  defp wait_for_service(sprite, service_name, timeout_ms) do
    wait_until(timeout_ms, 250, fn ->
      case Sprites.list_services(sprite) do
        {:ok, services} ->
          if Enum.any?(services, &(&1.name == service_name)) do
            {:ok, services}
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
