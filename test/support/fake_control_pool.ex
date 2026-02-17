defmodule Sprites.FakeControlPool do
  @moduledoc false

  use Agent

  @name __MODULE__

  @type stats :: %{
          start_calls: non_neg_integer(),
          checkout_calls: non_neg_integer()
        }

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) do
    ensure_started()

    Agent.get_and_update(@name, fn state ->
      cleanup(state)

      new_state = %{
        start_calls: 0,
        checkout_calls: 0,
        fail_checkout_once?: Keyword.get(opts, :fail_checkout_once, false),
        pools: MapSet.new(),
        conns: MapSet.new()
      }

      {:ok, new_state}
    end)
  end

  @spec stats() :: stats()
  def stats do
    ensure_started()

    Agent.get(@name, fn state ->
      %{start_calls: state.start_calls, checkout_calls: state.checkout_calls}
    end)
  end

  @spec start(keyword()) :: {:ok, pid()}
  def start(_opts) do
    ensure_started()
    pool = spawn_pool()

    Agent.update(@name, fn state ->
      %{state | start_calls: state.start_calls + 1, pools: MapSet.put(state.pools, pool)}
    end)

    {:ok, pool}
  end

  @spec checkout(pid()) :: {:ok, pid()}
  def checkout(pool) do
    ensure_started()

    if not Process.alive?(pool) do
      exit(:noproc)
    end

    action =
      Agent.get_and_update(@name, fn state ->
        if state.fail_checkout_once? do
          {:fail, %{state | fail_checkout_once?: false, checkout_calls: state.checkout_calls + 1}}
        else
          conn = spawn_conn()

          new_state = %{
            state
            | checkout_calls: state.checkout_calls + 1,
              conns: MapSet.put(state.conns, conn)
          }

          {{:ok, conn}, new_state}
        end
      end)

    case action do
      :fail ->
        exit({:noproc, {GenServer, :call, [pool, :checkout, 30_000]}})

      {:ok, conn} ->
        {:ok, conn}
    end
  end

  @spec checkin(pid(), pid()) :: :ok
  def checkin(_pool, conn) when is_pid(conn) do
    if Process.alive?(conn) do
      Process.exit(conn, :normal)
    end

    :ok
  end

  @spec close(pid()) :: :ok
  def close(pool) when is_pid(pool) do
    if Process.alive?(pool) do
      Process.exit(pool, :normal)
    end

    :ok
  end

  defp ensure_started do
    case Process.whereis(@name) do
      nil ->
        case Agent.start_link(fn -> empty_state() end, name: @name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp empty_state do
    %{
      start_calls: 0,
      checkout_calls: 0,
      fail_checkout_once?: false,
      pools: MapSet.new(),
      conns: MapSet.new()
    }
  end

  defp cleanup(state) do
    Enum.each(state.conns, fn pid ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    Enum.each(state.pools, fn pid ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)
  end

  defp spawn_pool do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp spawn_conn do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end
end
