defmodule Sprites.Control do
  @moduledoc """
  Module-level pool management for control connections.

  Uses ETS tables to store per-sprite pools and control support flags.
  Pools are created lazily on first checkout and cached for reuse.
  """

  alias Sprites.{ControlPool, Sprite}

  @pools_table :sprites_control_pools
  @support_table :sprites_control_support

  @doc """
  Ensures ETS tables exist. Safe to call multiple times.
  """
  @spec ensure_tables() :: :ok
  def ensure_tables do
    :ok = Sprites.Control.TableOwner.ensure_started()
    :ok
  end

  @doc """
  Checks out a control connection for the given sprite.

  Creates a pool if one doesn't exist yet.
  """
  @spec checkout(Sprite.t()) :: {:ok, pid()} | {:error, term()}
  def checkout(%Sprite{} = sprite) do
    ensure_tables()

    with {:ok, pool} <- get_or_create_pool(sprite),
         {:ok, conn_pid} <- checkout_pool(sprite, pool, 0) do
      {:ok, conn_pid}
    end
  end

  @doc """
  Returns a control connection to the pool for the given sprite.
  """
  @spec checkin(Sprite.t(), pid()) :: :ok
  def checkin(%Sprite{} = sprite, conn_pid) do
    ensure_tables()
    key = sprite_key(sprite)

    case :ets.lookup(@pools_table, key) do
      [{^key, pool}] ->
        pool_module().checkin(pool, conn_pid)

      [] ->
        :ok
    end
  end

  @doc """
  Returns whether control mode is believed to be supported for the given sprite.

  Returns `true` by default (until `mark_unsupported/1` is called).
  """
  @spec control_supported?(Sprite.t()) :: boolean()
  def control_supported?(%Sprite{} = sprite) do
    ensure_tables()
    key = sprite_key(sprite)

    case :ets.lookup(@support_table, key) do
      [{^key, false}] -> false
      _ -> true
    end
  end

  @doc """
  Marks a sprite as not supporting control mode.

  Prevents future checkout attempts from trying the control endpoint.
  """
  @spec mark_unsupported(Sprite.t()) :: :ok
  def mark_unsupported(%Sprite{} = sprite) do
    ensure_tables()
    key = sprite_key(sprite)
    :ets.insert(@support_table, {key, false})
    :ok
  end

  @doc """
  Closes all control connections for the given sprite and removes the pool.
  """
  @spec close(Sprite.t()) :: :ok
  def close(%Sprite{} = sprite) do
    ensure_tables()
    key = sprite_key(sprite)

    case :ets.lookup(@pools_table, key) do
      [{^key, pool}] ->
        pool_module().close(pool)
        :ets.delete(@pools_table, key)

      [] ->
        :ok
    end

    :ok
  end

  # Private helpers

  @spec get_or_create_pool(Sprite.t()) :: {:ok, pid()} | {:error, term()}
  defp get_or_create_pool(sprite) do
    key = sprite_key(sprite)

    case lookup_pool(key) do
      {:ok, pool} ->
        {:ok, pool}

      :not_found ->
        :global.trans(
          {{__MODULE__, key}, self()},
          fn ->
            case lookup_pool(key) do
              {:ok, pool} -> {:ok, pool}
              :not_found -> create_pool(sprite, key)
            end
          end,
          [node()]
        )
    end
  end

  @spec create_pool(Sprite.t(), term()) :: {:ok, pid()} | {:error, term()}
  defp create_pool(sprite, key) do
    url = Sprite.control_url(sprite)
    token = Sprite.token(sprite)

    with {:ok, pool} <- pool_module().start(url: url, token: token) do
      true = :ets.insert(@pools_table, {key, pool})
      {:ok, pool}
    end
  end

  @spec lookup_pool(term()) :: {:ok, pid()} | :not_found
  defp lookup_pool(key) do
    case :ets.lookup(@pools_table, key) do
      [{^key, pool}] when is_pid(pool) ->
        if Process.alive?(pool) do
          {:ok, pool}
        else
          :ets.delete(@pools_table, key)
          :not_found
        end

      _ ->
        :not_found
    end
  end

  @spec checkout_pool(Sprite.t(), pid(), non_neg_integer()) :: {:ok, pid()} | {:error, term()}
  defp checkout_pool(sprite, pool, attempt) do
    case safe_pool_checkout(pool) do
      {:ok, conn_pid} ->
        {:ok, conn_pid}

      {:error, reason} ->
        if attempt == 0 and retryable_checkout_error?(reason) do
          :ets.delete(@pools_table, sprite_key(sprite))

          with {:ok, new_pool} <- get_or_create_pool(sprite) do
            checkout_pool(sprite, new_pool, 1)
          end
        else
          {:error, reason}
        end
    end
  end

  @spec safe_pool_checkout(pid()) :: {:ok, pid()} | {:error, term()}
  defp safe_pool_checkout(pool) do
    try do
      pool_module().checkout(pool)
    catch
      :exit, reason -> {:error, {:checkout_exit, reason}}
    end
  end

  defp retryable_checkout_error?({:checkout_exit, reason}), do: stale_pool_exit?(reason)
  defp retryable_checkout_error?(_), do: false

  defp stale_pool_exit?(reason) do
    match?(:noproc, reason) or
      match?({:noproc, _}, reason) or
      match?({{:noproc, _}, _}, reason) or
      match?({:shutdown, {:noproc, _}}, reason) or
      match?({:shutdown, {{:noproc, _}, _}}, reason)
  end

  defp pool_module do
    Application.get_env(:sprites, :control_pool_module, ControlPool)
  end

  defp sprite_key(%Sprite{name: name, client: client}) do
    {client.base_url, name}
  end
end
