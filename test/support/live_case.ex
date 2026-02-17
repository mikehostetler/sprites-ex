defmodule Sprites.LiveCase do
  @moduledoc """
  Helpers for live API tests.

  Live tests are tagged with `:live` and `:integration`, and are skipped
  automatically if `SPRITES_TEST_TOKEN` is not present.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Sprites.LiveCase
    end
  end

  setup _tags do
    token = System.get_env("SPRITES_TEST_TOKEN")
    base_url = System.get_env("SPRITES_TEST_BASE_URL", "https://api.sprites.dev")
    {:ok, token: token, base_url: base_url}
  end

  def client!(token, base_url, opts \\ []) do
    Sprites.new(token, Keyword.merge([base_url: base_url], opts))
  end

  def unique_sprite_name(prefix \\ "sprites-ex") do
    suffix = System.unique_integer([:positive, :monotonic])
    "#{prefix}-#{suffix}"
  end
end
