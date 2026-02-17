defmodule Sprites.Control.TableOwner do
  @moduledoc false

  use GenServer

  @name __MODULE__
  @pools_table :sprites_control_pools
  @support_table :sprites_control_support

  @spec ensure_started() :: :ok
  def ensure_started do
    case Process.whereis(@name) do
      nil ->
        case GenServer.start(__MODULE__, :ok, name: @name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} -> :ok
        end

      _pid ->
        :ok
    end
  end

  @impl true
  def init(:ok) do
    ensure_named_table(@pools_table)
    ensure_named_table(@support_table)
    {:ok, %{}}
  end

  defp ensure_named_table(table) do
    case :ets.whereis(table) do
      :undefined ->
        try do
          :ets.new(table, [
            :named_table,
            :public,
            :set,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end
end
