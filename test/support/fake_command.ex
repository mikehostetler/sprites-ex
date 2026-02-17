defmodule Sprites.FakeCommand do
  @moduledoc false

  @spec start(term(), String.t(), [String.t()], keyword()) ::
          {:ok, Sprites.Command.t()} | {:error, term()}
  def start(_sprite, _command, _args, opts) do
    owner = Keyword.get(opts, :owner, self())
    ref = make_ref()

    cmd = %Sprites.Command{
      ref: ref,
      pid: self(),
      sprite: nil,
      owner: owner,
      tty_mode: false
    }

    opts
    |> Keyword.get(:test_events, [])
    |> Enum.each(&dispatch_event(owner, ref, &1))

    {:ok, cmd}
  end

  @spec stop(Sprites.Command.t()) :: :ok
  def stop(%Sprites.Command{ref: ref}) do
    send(self(), {:fake_command_stop, ref})
    :ok
  end

  defp dispatch_event(owner, ref, {:after, delay_ms, event}) do
    Process.send_after(owner, encode_event(ref, event), delay_ms)
  end

  defp dispatch_event(owner, ref, event) do
    send(owner, encode_event(ref, event))
  end

  defp encode_event(ref, {:stdout, data}), do: {:stdout, %{ref: ref}, data}
  defp encode_event(ref, {:stderr, data}), do: {:stderr, %{ref: ref}, data}
  defp encode_event(ref, {:exit, code}), do: {:exit, %{ref: ref}, code}
  defp encode_event(ref, {:error, reason}), do: {:error, %{ref: ref}, reason}
end
