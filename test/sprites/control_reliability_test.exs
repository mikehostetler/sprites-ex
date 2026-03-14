defmodule Sprites.ControlReliabilityTest do
  use ExUnit.Case, async: false

  alias Sprites.{Client, Control, FakeControlPool, Sprite}

  setup do
    previous_module = Application.get_env(:sprites, :control_pool_module)
    Application.put_env(:sprites, :control_pool_module, FakeControlPool)

    :ok = FakeControlPool.reset()
    :ok = Control.ensure_tables()
    clear_control_tables()

    on_exit(fn ->
      clear_control_tables()
      :ok = FakeControlPool.reset()

      if previous_module do
        Application.put_env(:sprites, :control_pool_module, previous_module)
      else
        Application.delete_env(:sprites, :control_pool_module)
      end
    end)

    :ok
  end

  test "checkout retries with a fresh pool after stale checkout exit" do
    :ok = FakeControlPool.reset(fail_checkout_once: true)
    sprite = Sprite.new(Client.new("token"), "retry-sprite")

    assert {:ok, conn} = Control.checkout(sprite)
    assert is_pid(conn)

    assert %{start_calls: 2, checkout_calls: 2} = FakeControlPool.stats()
  end

  test "concurrent checkouts create a single pool" do
    sprite = Sprite.new(Client.new("token"), "race-sprite")

    results =
      1..20
      |> Enum.map(fn _ ->
        Task.async(fn -> Control.checkout(sprite) end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.all?(results, &match?({:ok, pid} when is_pid(pid), &1))
    assert %{start_calls: 1} = FakeControlPool.stats()
  end

  defp clear_control_tables do
    for table <- [:sprites_control_pools, :sprites_control_support] do
      case :ets.whereis(table) do
        :undefined -> :ok
        _tid -> :ets.delete_all_objects(table)
      end
    end
  end
end
