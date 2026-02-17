defmodule Sprites.LiveCase do
  @moduledoc """
  Helpers for live API tests.

  Live tests are tagged with `:live` and `:integration`, and are skipped
  automatically if `SPRITES_TEST_TOKEN` is not present.
  """

  use ExUnit.CaseTemplate

  @env_loaded_key {__MODULE__, :env_loaded}

  using do
    quote do
      import Sprites.LiveCase
    end
  end

  setup _tags do
    token = live_token()
    base_url = live_base_url()
    {:ok, token: token, base_url: base_url}
  end

  @spec live_token() :: String.t() | nil
  def live_token do
    ensure_env_loaded()
    System.get_env("SPRITES_TEST_TOKEN") || System.get_env("SPRITE_TOKEN")
  end

  @spec live_base_url() :: String.t()
  def live_base_url do
    ensure_env_loaded()

    System.get_env("SPRITES_TEST_BASE_URL") || System.get_env("SPRITE_BASE_URL") ||
      "https://api.sprites.dev"
  end

  def client!(token, base_url, opts \\ []) do
    Sprites.new(token, Keyword.merge([base_url: base_url], opts))
  end

  def unique_sprite_name(prefix \\ "sprites-ex") do
    suffix = System.unique_integer([:positive, :monotonic])
    "#{prefix}-#{suffix}"
  end

  defp ensure_env_loaded do
    case :persistent_term.get(@env_loaded_key, false) do
      true ->
        :ok

      false ->
        maybe_load_dotenv()
        :persistent_term.put(@env_loaded_key, true)
        :ok
    end
  end

  defp maybe_load_dotenv do
    if File.exists?(".env") do
      ".env"
      |> File.stream!()
      |> Enum.each(&load_env_line/1)
    end
  end

  defp load_env_line(line) do
    line = String.trim(line)

    cond do
      line == "" ->
        :ok

      String.starts_with?(line, "#") ->
        :ok

      true ->
        case Regex.run(~r/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/, line) do
          [_, key, raw_value] ->
            if System.get_env(key) in [nil, ""] do
              System.put_env(key, normalize_env_value(raw_value))
            end

          _ ->
            :ok
        end
    end
  end

  defp normalize_env_value(raw_value) do
    value = String.trim(raw_value)

    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        value
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        value
        |> String.trim_leading("'")
        |> String.trim_trailing("'")

      true ->
        value
    end
  end
end
