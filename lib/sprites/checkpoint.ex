defmodule Sprites.Checkpoint do
  @moduledoc """
  Checkpoint management for sprites.

  Checkpoints allow you to save and restore the state of a sprite.
  """

  alias Sprites.{Client, Sprite, HTTP, NDJSONStream, Shapes, StreamMessage}

  @doc """
  Represents a checkpoint.

  ## Fields

    * `:id` - Unique checkpoint identifier
    * `:create_time` - When the checkpoint was created (DateTime)
    * `:history` - List of parent checkpoint IDs
    * `:comment` - Optional user-provided comment
    * `:raw` - Original API response map
  """
  @type t :: %__MODULE__{
          id: String.t(),
          create_time: DateTime.t() | nil,
          history: [String.t()],
          comment: String.t() | nil,
          raw: map() | nil
        }

  defstruct [:id, :create_time, :comment, :raw, history: []]

  @doc """
  Creates a checkpoint from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    create_time =
      case Map.get(map, "create_time") || Map.get(map, :create_time) do
        nil -> nil
        ts when is_binary(ts) -> parse_datetime(ts)
        ts -> ts
      end

    %__MODULE__{
      id: Map.get(map, "id") || Map.get(map, :id),
      create_time: create_time,
      history: Map.get(map, "history") || Map.get(map, :history) || [],
      comment: Map.get(map, "comment") || Map.get(map, :comment),
      raw: map
    }
  end

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  @doc """
  Lists all checkpoints for a sprite.

  ## Options

    * `:history` - History filter string (optional)

  ## Examples

      {:ok, checkpoints} = Sprites.Checkpoint.list(sprite)
  """
  @spec list(Sprite.t(), keyword()) :: {:ok, [t()]} | {:error, term()}
  def list(%Sprite{client: client, name: name}, opts \\ []) do
    list_by_name(client, name, opts)
  end

  @doc """
  Lists all checkpoints for a sprite by name.
  """
  @spec list_by_name(Client.t(), String.t(), keyword()) :: {:ok, [t()]} | {:error, term()}
  def list_by_name(%Client{} = client, name, opts \\ []) when is_binary(name) do
    params =
      case Keyword.get(opts, :history) do
        nil -> []
        filter -> [history: filter]
      end

    with {:ok, body} <-
           client.req
           |> HTTP.get(url: "/v1/sprites/#{URI.encode(name)}/checkpoints", params: params)
           |> HTTP.unwrap_body() do
      case body do
        list when is_list(list) ->
          {:ok, Enum.map(list, &checkpoint_from_api/1)}

        _ ->
          {:error, {:unexpected_response_shape, body}}
      end
    end
  end

  @doc """
  Gets a specific checkpoint by ID.

  ## Examples

      {:ok, checkpoint} = Sprites.Checkpoint.get(sprite, "checkpoint-id")
  """
  @spec get(Sprite.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def get(%Sprite{client: client, name: name}, checkpoint_id) do
    get_by_name(client, name, checkpoint_id)
  end

  @doc """
  Gets a specific checkpoint by sprite name and checkpoint ID.
  """
  @spec get_by_name(Client.t(), String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def get_by_name(%Client{} = client, name, checkpoint_id) when is_binary(name) do
    with {:ok, body} <-
           client.req
           |> HTTP.get(
             url: "/v1/sprites/#{URI.encode(name)}/checkpoints/#{URI.encode(checkpoint_id)}"
           )
           |> HTTP.unwrap_body() do
      {:ok, checkpoint_from_api(body)}
    end
  end

  @doc """
  Creates a new checkpoint for a sprite.

  Returns a stream of messages. The stream should be consumed to completion.

  ## Options

    * `:comment` - Optional comment for the checkpoint

  ## Examples

      {:ok, stream} = Sprites.Checkpoint.create(sprite, comment: "Before changes")
      Enum.each(stream, fn msg -> IO.inspect(msg) end)
  """
  @spec create(Sprite.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def create(%Sprite{client: client, name: name}, opts \\ []) do
    create_by_name(client, name, opts)
  end

  @doc """
  Creates a new checkpoint for a sprite by name.
  """
  @spec create_by_name(Client.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def create_by_name(%Client{} = client, name, opts \\ []) when is_binary(name) do
    json =
      case Keyword.get(opts, :comment) do
        nil -> %{}
        "" -> %{}
        comment -> %{comment: comment}
      end

    NDJSONStream.request(client, :post, "/v1/sprites/#{URI.encode(name)}/checkpoint",
      json: json,
      parser: &parse_stream_message/1
    )
  end

  @doc """
  Restores a sprite from a checkpoint.

  Returns a stream of messages. The stream should be consumed to completion.

  ## Examples

      {:ok, stream} = Sprites.Checkpoint.restore(sprite, "checkpoint-id")
      Enum.each(stream, fn msg -> IO.inspect(msg) end)
  """
  @spec restore(Sprite.t(), String.t()) :: {:ok, Enumerable.t()} | {:error, term()}
  def restore(%Sprite{client: client, name: name}, checkpoint_id) do
    restore_by_name(client, name, checkpoint_id)
  end

  @doc """
  Restores a sprite from a checkpoint by name.
  """
  @spec restore_by_name(Client.t(), String.t(), String.t()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def restore_by_name(%Client{} = client, name, checkpoint_id) when is_binary(name) do
    NDJSONStream.request(
      client,
      :post,
      "/v1/sprites/#{URI.encode(name)}/checkpoints/#{URI.encode(checkpoint_id)}/restore",
      parser: &parse_stream_message/1
    )
  end

  defp checkpoint_from_api(map) do
    case Shapes.parse_checkpoint(map) do
      {:ok, parsed} -> from_map(parsed)
      {:error, _reason} -> from_map(map)
    end
  end

  defp parse_stream_message(map) do
    case Shapes.parse_checkpoint_event(map) do
      {:ok, parsed} -> StreamMessage.from_map(parsed, map)
      {:error, _reason} -> StreamMessage.from_map(map, map)
    end
  end
end

defmodule Sprites.StreamMessage do
  @moduledoc """
  A message from a streaming operation (checkpoint create/restore).

  ## Fields

    * `:type` - Message type (for example: "info", "error", "complete")
    * `:data` - Message data
    * `:error` - Error string (if present)
    * `:message` - Event message (if present)
    * `:time` - ISO8601 timestamp string (if present)
    * `:timestamp` - Unix millisecond timestamp (if present)
    * `:exit_code` - Exit code (if present)
    * `:signal` - Signal name (if present)
    * `:pid` - Process ID (if present)
    * `:log_files` - Map of log file paths (if present)
    * `:raw` - Original event map
  """
  @type t :: %__MODULE__{
          type: String.t() | nil,
          data: String.t() | nil,
          error: String.t() | nil,
          message: String.t() | nil,
          time: String.t() | nil,
          timestamp: number() | nil,
          exit_code: number() | nil,
          signal: String.t() | nil,
          pid: integer() | nil,
          log_files: map() | nil,
          raw: map() | nil
        }

  defstruct [
    :type,
    :data,
    :error,
    :message,
    :time,
    :timestamp,
    :exit_code,
    :signal,
    :pid,
    :log_files,
    :raw
  ]

  alias Sprites.Shapes

  @doc """
  Creates a stream message from a map.
  """
  @spec from_map(map(), map() | nil) :: t()
  def from_map(map, raw \\ nil) when is_map(map) do
    parsed =
      map
      |> normalize_stream_message()
      |> parse_stream_message()

    %__MODULE__{
      type: Map.get(parsed, "type"),
      data: Map.get(parsed, "data"),
      error: Map.get(parsed, "error"),
      message: Map.get(parsed, "message"),
      time: Map.get(parsed, "time"),
      timestamp: Map.get(parsed, "timestamp"),
      exit_code: Map.get(parsed, "exit_code"),
      signal: Map.get(parsed, "signal"),
      pid: Map.get(parsed, "pid"),
      log_files: Map.get(parsed, "log_files"),
      raw: raw || map
    }
  end

  @doc """
  Converts a stream message to a map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = msg) do
    %{}
    |> maybe_put(:type, msg.type)
    |> maybe_put(:data, msg.data)
    |> maybe_put(:error, msg.error)
    |> maybe_put(:message, msg.message)
    |> maybe_put(:time, msg.time)
    |> maybe_put(:timestamp, msg.timestamp)
    |> maybe_put(:exit_code, msg.exit_code)
    |> maybe_put(:signal, msg.signal)
    |> maybe_put(:pid, msg.pid)
    |> maybe_put(:log_files, msg.log_files)
  end

  defp normalize_stream_message(map) do
    %{}
    |> maybe_put("type", field(map, "type", :type))
    |> maybe_put("data", field(map, "data", :data))
    |> maybe_put("error", field(map, "error", :error))
    |> maybe_put("message", field(map, "message", :message))
    |> maybe_put("time", field(map, "time", :time))
    |> maybe_put("timestamp", field(map, "timestamp", :timestamp))
    |> maybe_put("exit_code", field(map, "exit_code", :exit_code))
    |> maybe_put("signal", field(map, "signal", :signal))
    |> maybe_put("pid", field(map, "pid", :pid))
    |> maybe_put("log_files", field(map, "log_files", :log_files))
  end

  defp parse_stream_message(map) do
    case Shapes.parse_stream_message(map) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> map
    end
  end

  defp field(map, string_key, atom_key) do
    Map.get(map, string_key) || Map.get(map, atom_key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
