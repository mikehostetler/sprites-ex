defmodule Sprites.Session do
  @moduledoc """
  Session management for sprites.

  Sessions represent active command executions that can be listed, attached to,
  and explicitly terminated.
  """

  alias Sprites.{Client, Sprite, HTTP, NDJSONStream, Shapes, StreamMessage}

  @doc """
  Represents an active execution session.

  ## Fields

    * `:id` - Unique session identifier
    * `:command` - The command being executed
    * `:workdir` - Working directory
    * `:created` - When the session was created (DateTime)
    * `:bytes_per_second` - Throughput rate
    * `:is_active` - Whether the session is currently active
    * `:last_activity` - Time of last activity (DateTime)
    * `:tty` - Whether TTY is enabled
    * `:raw` - Original API response map
  """
  @type t :: %__MODULE__{
          id: String.t() | integer(),
          command: String.t(),
          workdir: String.t() | nil,
          created: DateTime.t() | nil,
          bytes_per_second: float(),
          is_active: boolean(),
          last_activity: DateTime.t() | nil,
          tty: boolean(),
          raw: map() | nil
        }

  defstruct [
    :id,
    :command,
    :workdir,
    :created,
    :last_activity,
    :raw,
    bytes_per_second: 0.0,
    is_active: false,
    tty: false
  ]

  @doc """
  Creates a session from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    created = parse_datetime(Map.get(map, "created") || Map.get(map, :created))
    last_activity = parse_datetime(Map.get(map, "last_activity") || Map.get(map, :last_activity))

    %__MODULE__{
      id: Map.get(map, "id") || Map.get(map, :id),
      command: Map.get(map, "command") || Map.get(map, :command),
      workdir: Map.get(map, "workdir") || Map.get(map, :workdir),
      created: created,
      bytes_per_second:
        Map.get(map, "bytes_per_second") || Map.get(map, :bytes_per_second) || 0.0,
      is_active: Map.get(map, "is_active") || Map.get(map, :is_active) || false,
      last_activity: last_activity,
      tty: Map.get(map, "tty") || Map.get(map, :tty) || false,
      raw: map
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(other), do: other

  @doc """
  Lists all active sessions for a sprite.

  ## Examples

      {:ok, sessions} = Sprites.Session.list(sprite)
  """
  @spec list(Sprite.t()) :: {:ok, [t()]} | {:error, term()}
  def list(%Sprite{client: client, name: name}) do
    list_by_name(client, name)
  end

  @doc """
  Lists all active sessions for a sprite by name.
  """
  @spec list_by_name(Client.t(), String.t()) :: {:ok, [t()]} | {:error, term()}
  def list_by_name(%Client{} = client, name) when is_binary(name) do
    with {:ok, body} <-
           client.req
           |> HTTP.get(url: "/v1/sprites/#{URI.encode(name)}/exec")
           |> HTTP.unwrap_body(),
         {:ok, sessions} <- extract_sessions(body) do
      parsed_sessions =
        Enum.map(sessions, fn session ->
          case Shapes.parse_session(session) do
            {:ok, parsed} -> from_map(parsed)
            {:error, _reason} -> from_map(session)
          end
        end)

      {:ok, parsed_sessions}
    end
  end

  @doc """
  Kills an active session for a sprite.

  Returns an NDJSON event stream describing kill progress.

  ## Options

    * `:signal` - Signal name (for example "SIGTERM")
    * `:timeout` - Wait duration (for example "10s")
  """
  @spec kill(Sprite.t(), String.t() | integer(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def kill(%Sprite{client: client, name: name}, session_id, opts \\ []) do
    kill_by_name(client, name, session_id, opts)
  end

  @doc """
  Kills an active session by sprite name and session ID.
  """
  @spec kill_by_name(Client.t(), String.t(), String.t() | integer(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def kill_by_name(%Client{} = client, name, session_id, opts \\ []) when is_binary(name) do
    params =
      []
      |> maybe_put_param(:signal, Keyword.get(opts, :signal))
      |> maybe_put_param(:timeout, Keyword.get(opts, :timeout))

    NDJSONStream.request(
      client,
      :post,
      "/v1/sprites/#{URI.encode(name)}/exec/#{URI.encode(to_string(session_id))}/kill",
      params: params,
      parser: &parse_kill_event/1
    )
  end

  @doc """
  Returns true if the session has recent activity (within 5 minutes).
  """
  @spec is_session_active?(t()) :: boolean()
  def is_session_active?(%__MODULE__{is_active: false}), do: false
  def is_session_active?(%__MODULE__{is_active: true, last_activity: nil}), do: true

  def is_session_active?(%__MODULE__{is_active: true, last_activity: last_activity}) do
    case DateTime.diff(DateTime.utc_now(), last_activity, :second) do
      diff when diff < 300 -> true
      _ -> false
    end
  end

  @doc """
  Returns how long ago the last activity was.
  """
  @spec get_activity_age(t()) :: integer()
  def get_activity_age(%__MODULE__{last_activity: nil, created: nil}), do: 0

  def get_activity_age(%__MODULE__{last_activity: nil, created: created}) do
    DateTime.diff(DateTime.utc_now(), created, :second)
  end

  def get_activity_age(%__MODULE__{last_activity: last_activity}) do
    DateTime.diff(DateTime.utc_now(), last_activity, :second)
  end

  defp parse_kill_event(event) do
    case Shapes.parse_exec_kill_event(event) do
      {:ok, parsed} -> StreamMessage.from_map(parsed, event)
      {:error, _reason} -> StreamMessage.from_map(event, event)
    end
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: params ++ [{key, value}]

  defp extract_sessions(%{"sessions" => sessions}) when is_list(sessions),
    do: ensure_map_list(sessions)

  defp extract_sessions(sessions) when is_list(sessions), do: ensure_map_list(sessions)
  defp extract_sessions(other), do: {:error, {:unexpected_response_shape, other}}

  defp ensure_map_list(items) do
    if Enum.all?(items, &is_map/1) do
      {:ok, items}
    else
      {:error, {:unexpected_response_shape, items}}
    end
  end
end
