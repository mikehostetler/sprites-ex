defmodule Sprites.Stream do
  @moduledoc """
  Provides an Elixir Stream-based interface for command output.

  This allows processing command output lazily and composing with
  other Stream operations.

  ## Example

      sprite
      |> Sprites.stream("tail", ["-f", "/var/log/app.log"])
      |> Stream.filter(&String.contains?(&1, "ERROR"))
      |> Stream.each(&Logger.error/1)
      |> Stream.run()
  """

  @doc """
  Creates a new stream that emits command output chunks.

  The stream will emit stdout data as binary chunks.
  Stderr is not included in the stream (use `Sprites.spawn/4` for full control).

  ## Options

  Same as `Sprites.spawn/4`, plus:

    * `:idle_timeout` - Max idle wait for the next event in milliseconds (default: `:infinity`)
  """
  @spec new(Sprites.Sprite.t(), String.t(), [String.t()], keyword()) :: Enumerable.t()
  def new(sprite, command, args, opts) do
    idle_timeout = Keyword.get(opts, :idle_timeout, :infinity)

    Stream.resource(
      fn -> start_command(sprite, command, args, opts, idle_timeout) end,
      &next_chunk/1,
      &cleanup/1
    )
  end

  defp start_command(sprite, command, args, opts, idle_timeout) do
    case command_module().start(sprite, command, args, opts) do
      {:ok, cmd} -> {:running, cmd, idle_timeout}
      {:error, reason} -> {:error, reason}
    end
  end

  defp next_chunk({:error, reason}) do
    raise "Stream error: #{inspect(reason)}"
  end

  defp next_chunk({:done, cmd, idle_timeout}) do
    {:halt, {:done, cmd, idle_timeout}}
  end

  defp next_chunk({:running, cmd, idle_timeout}) do
    ref = cmd.ref

    receive do
      {:stdout, %{ref: ^ref}, data} ->
        {[data], {:running, cmd, idle_timeout}}

      {:stderr, %{ref: ^ref}, _data} ->
        # Skip stderr in stream mode
        {[], {:running, cmd, idle_timeout}}

      {:exit, %{ref: ^ref}, _code} ->
        {:halt, {:done, cmd, idle_timeout}}

      {:error, %{ref: ^ref}, reason} ->
        command_module().stop(cmd)
        raise "Stream error: #{inspect(reason)}"
    after
      idle_timeout ->
        {:halt, {:running, cmd, idle_timeout}}
    end
  end

  defp cleanup({:done, _cmd, _idle_timeout}) do
    :ok
  end

  defp cleanup({:running, cmd, _idle_timeout}) do
    # Stop the command if the consumer halted early.
    # This prevents leaked remote executions when callers use take/first.
    command_module().stop(cmd)
    :ok
  end

  defp cleanup({:error, _reason}) do
    :ok
  end

  defp command_module do
    Application.get_env(:sprites, :command_module, Sprites.Command)
  end
end
