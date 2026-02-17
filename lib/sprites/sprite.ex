defmodule Sprites.Sprite do
  @moduledoc """
  Represents a sprite instance.
  """

  defstruct [:name, :client, :id, :status, :config, :environment, :raw]

  @type t :: %__MODULE__{
          name: String.t(),
          client: Sprites.Client.t(),
          id: String.t() | nil,
          status: String.t() | nil,
          config: map() | nil,
          environment: map() | nil,
          raw: map() | nil
        }

  @doc """
  Creates a new sprite handle.
  """
  @spec new(Sprites.Client.t(), String.t(), map()) :: t()
  def new(client, name, attrs \\ %{}) do
    %__MODULE__{
      name: name,
      client: client,
      id: Map.get(attrs, "id"),
      status: Map.get(attrs, "status"),
      config: Map.get(attrs, "config"),
      environment: Map.get(attrs, "environment"),
      raw: attrs
    }
  end

  @doc """
  Destroys this sprite.
  """
  @spec destroy(t()) :: :ok | {:error, term()}
  def destroy(%__MODULE__{client: client, name: name}) do
    Sprites.Client.delete_sprite(client, name)
  end

  @doc """
  Builds the WebSocket URL for command execution.
  """
  @spec exec_url(t(), String.t(), [String.t()], keyword()) :: String.t()
  def exec_url(%__MODULE__{client: client, name: name}, command, args, opts) do
    base =
      client.base_url
      |> String.replace(~r/^http/, "ws")

    path = "/v1/sprites/#{URI.encode(name)}/exec"
    query_params = build_exec_query_params(command, args, opts)

    "#{base}#{path}?#{URI.encode_query(query_params)}"
  end

  @doc """
  Builds the WebSocket URL for attaching to an existing session.
  """
  @spec attach_url(t(), String.t() | integer(), keyword()) :: String.t()
  def attach_url(%__MODULE__{client: client, name: name}, session_id, opts \\ []) do
    base =
      client.base_url
      |> String.replace(~r/^http/, "ws")

    path = "/v1/sprites/#{URI.encode(name)}/exec/#{URI.encode(to_string(session_id))}"
    query_params = build_attach_query_params(opts)

    if query_params == [] do
      "#{base}#{path}"
    else
      "#{base}#{path}?#{URI.encode_query(query_params)}"
    end
  end

  @doc """
  Builds the legacy WebSocket attach URL using `/exec?session_id=...`.
  """
  @spec legacy_attach_url(t(), String.t() | integer(), keyword()) :: String.t()
  def legacy_attach_url(%__MODULE__{client: client, name: name}, session_id, opts \\ []) do
    base =
      client.base_url
      |> String.replace(~r/^http/, "ws")

    path = "/v1/sprites/#{URI.encode(name)}/exec"

    query_params =
      [{"session_id", to_string(session_id)} | build_attach_query_params(opts)]

    "#{base}#{path}?#{URI.encode_query(query_params)}"
  end

  @doc """
  Builds the WebSocket URL for the control endpoint.
  """
  @spec control_url(t()) :: String.t()
  def control_url(%__MODULE__{client: client, name: name}) do
    base =
      client.base_url
      |> String.replace(~r/^http/, "ws")

    "#{base}/v1/sprites/#{URI.encode(name)}/control"
  end

  @doc """
  Returns whether control mode is enabled for this sprite's client.
  """
  @spec control_mode?(t()) :: boolean()
  def control_mode?(%__MODULE__{client: client}) do
    client.control_mode
  end

  @doc """
  Returns the authorization token for this sprite's client.
  """
  @spec token(t()) :: String.t()
  def token(%__MODULE__{client: client}) do
    client.token
  end

  @doc """
  Builds a path for sprite-specific API endpoints.
  """
  @spec path(t(), String.t(), keyword() | map()) :: String.t()
  def path(%__MODULE__{name: name}, endpoint, params \\ []) do
    query = if params in [[], %{}], do: "", else: "?#{URI.encode_query(params)}"
    "/v1/sprites/#{URI.encode(name)}#{endpoint}#{query}"
  end

  defp build_exec_query_params(command, args, opts) do
    [{"path", command} | Enum.map([command | args], &{"cmd", &1})]
    |> add_stdin_param(opts)
    |> add_dir_param(opts)
    |> add_env_params(opts)
    |> add_tty_params(opts)
    |> add_detachable_param(opts)
    |> add_max_run_after_disconnect_param(opts)
  end

  defp build_attach_query_params(opts) do
    []
    |> add_stdin_param(opts)
    |> add_dir_param(opts)
    |> add_env_params(opts)
    |> add_tty_params(opts)
    |> add_max_run_after_disconnect_param(opts)
  end

  defp add_stdin_param(params, opts) do
    case Keyword.fetch(opts, :stdin) do
      {:ok, stdin} -> [{"stdin", if(stdin, do: "true", else: "false")} | params]
      :error -> params
    end
  end

  defp add_dir_param(params, opts) do
    case Keyword.get(opts, :dir) do
      nil -> params
      dir -> [{"dir", dir} | params]
    end
  end

  defp add_env_params(params, opts) do
    case Keyword.get(opts, :env, []) do
      [] -> params
      env_list -> Enum.map(env_list, fn {k, v} -> {"env", "#{k}=#{v}"} end) ++ params
    end
  end

  defp add_tty_params(params, opts) do
    case Keyword.fetch(opts, :tty) do
      {:ok, true} ->
        rows = Keyword.get(opts, :tty_rows, 24)
        cols = Keyword.get(opts, :tty_cols, 80)
        [{"tty", "true"}, {"rows", to_string(rows)}, {"cols", to_string(cols)} | params]

      {:ok, false} ->
        [{"tty", "false"} | params]

      :error ->
        params
    end
  end

  defp add_detachable_param(params, opts) do
    if Keyword.get(opts, :detachable, false) do
      [{"detachable", "true"} | params]
    else
      params
    end
  end

  defp add_max_run_after_disconnect_param(params, opts) do
    case Keyword.get(opts, :max_run_after_disconnect) do
      nil -> params
      value -> [{"max_run_after_disconnect", to_string(value)} | params]
    end
  end
end
