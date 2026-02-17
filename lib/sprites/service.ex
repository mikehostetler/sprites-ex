defmodule Sprites.Service do
  @moduledoc """
  Services API for persistent background processes running inside a sprite.
  """

  alias Sprites.{Client, Sprite, HTTP, NDJSONStream, Shapes, StreamMessage}

  defmodule State do
    @moduledoc """
    Runtime service state.
    """

    @type t :: %__MODULE__{
            name: String.t() | nil,
            status: String.t() | nil,
            pid: integer() | nil,
            started_at: DateTime.t() | nil,
            error: String.t() | nil,
            raw: map() | nil
          }

    defstruct [:name, :status, :pid, :started_at, :error, :raw]

    @spec from_map(map()) :: t()
    def from_map(map) when is_map(map) do
      %__MODULE__{
        name: Map.get(map, "name") || Map.get(map, :name),
        status: Map.get(map, "status") || Map.get(map, :status),
        pid: Map.get(map, "pid") || Map.get(map, :pid),
        started_at: parse_datetime(Map.get(map, "started_at") || Map.get(map, :started_at)),
        error: Map.get(map, "error") || Map.get(map, :error),
        raw: map
      }
    end

    defp parse_datetime(nil), do: nil

    defp parse_datetime(value) when is_binary(value) do
      case DateTime.from_iso8601(value) do
        {:ok, dt, _offset} -> dt
        _ -> nil
      end
    end

    defp parse_datetime(_), do: nil
  end

  @type t :: %__MODULE__{
          name: String.t(),
          cmd: String.t(),
          args: [String.t()],
          needs: [String.t()],
          http_port: integer() | nil,
          state: State.t() | nil,
          raw: map() | nil
        }

  defstruct [:name, :cmd, :http_port, :state, :raw, args: [], needs: []]

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    parsed =
      case Shapes.parse_service(map) do
        {:ok, parsed} -> parsed
        {:error, _reason} -> map
      end

    state =
      case Map.get(parsed, "state") || Map.get(parsed, :state) do
        %{} = s -> State.from_map(s)
        _ -> nil
      end

    %__MODULE__{
      name: Map.get(parsed, "name") || Map.get(parsed, :name),
      cmd: Map.get(parsed, "cmd") || Map.get(parsed, :cmd),
      args: Map.get(parsed, "args") || Map.get(parsed, :args) || [],
      needs: Map.get(parsed, "needs") || Map.get(parsed, :needs) || [],
      http_port: Map.get(parsed, "http_port") || Map.get(parsed, :http_port),
      state: state,
      raw: map
    }
  end

  @doc """
  List all services for a sprite.
  """
  @spec list(Sprite.t()) :: {:ok, [t()]} | {:error, term()}
  def list(%Sprite{client: client, name: name}) do
    list_by_name(client, name)
  end

  @doc """
  List all services for a sprite by name.
  """
  @spec list_by_name(Client.t(), String.t()) :: {:ok, [t()]} | {:error, term()}
  def list_by_name(%Client{} = client, name) when is_binary(name) do
    with {:ok, body} <-
           client.req
           |> HTTP.get(url: "/v1/sprites/#{URI.encode(name)}/services")
           |> HTTP.unwrap_body() do
      services =
        case body do
          list when is_list(list) -> list
          %{"services" => list} when is_list(list) -> list
          _ -> []
        end

      {:ok, Enum.map(services, &from_map/1)}
    end
  end

  @doc """
  Get a specific service by name.
  """
  @spec get(Sprite.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def get(%Sprite{client: client, name: name}, service_name) do
    get_by_name(client, name, service_name)
  end

  @doc """
  Get a specific service by sprite name and service name.
  """
  @spec get_by_name(Client.t(), String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def get_by_name(%Client{} = client, name, service_name) when is_binary(name) do
    with {:ok, body} <-
           client.req
           |> HTTP.get(
             url: "/v1/sprites/#{URI.encode(name)}/services/#{URI.encode(service_name)}"
           )
           |> HTTP.unwrap_body() do
      {:ok, from_map(body)}
    end
  end

  @doc """
  Create or update a service definition via `PUT`.

  ## Options

    * `:duration` - Time to monitor startup logs after apply
  """
  @spec upsert(Sprite.t(), String.t(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def upsert(%Sprite{client: client, name: name}, service_name, attrs, opts \\ []) do
    upsert_by_name(client, name, service_name, attrs, opts)
  end

  @doc """
  Create or update a service definition by sprite name.
  """
  @spec upsert_by_name(Client.t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def upsert_by_name(%Client{} = client, name, service_name, attrs, opts \\ [])
      when is_binary(name) and is_map(attrs) do
    params = [] |> maybe_put_param(:duration, Keyword.get(opts, :duration))

    with {:ok, body} <-
           client.req
           |> HTTP.put(
             url: "/v1/sprites/#{URI.encode(name)}/services/#{URI.encode(service_name)}",
             params: params,
             json: normalize_upsert_payload(attrs)
           )
           |> HTTP.unwrap_body() do
      {:ok, from_map(body)}
    end
  end

  @doc """
  Start a service and stream startup/log events.

  ## Options

    * `:duration` - Time to continue following logs after start (default server-side: `5s`)
  """
  @spec start(Sprite.t(), String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def start(%Sprite{client: client, name: name}, service_name, opts \\ []) do
    start_by_name(client, name, service_name, opts)
  end

  @doc """
  Start a service by sprite name.
  """
  @spec start_by_name(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def start_by_name(%Client{} = client, name, service_name, opts \\ []) when is_binary(name) do
    params = [] |> maybe_put_param(:duration, Keyword.get(opts, :duration))

    NDJSONStream.request(
      client,
      :post,
      "/v1/sprites/#{URI.encode(name)}/services/#{URI.encode(service_name)}/start",
      params: params,
      parser: &parse_service_event/1
    )
  end

  @doc """
  Stop a service and stream shutdown events.

  ## Options

    * `:timeout` - Time to wait for clean stop (default server-side: `10s`)
  """
  @spec stop(Sprite.t(), String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stop(%Sprite{client: client, name: name}, service_name, opts \\ []) do
    stop_by_name(client, name, service_name, opts)
  end

  @doc """
  Stop a service by sprite name.
  """
  @spec stop_by_name(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stop_by_name(%Client{} = client, name, service_name, opts \\ []) when is_binary(name) do
    params = [] |> maybe_put_param(:timeout, Keyword.get(opts, :timeout))

    NDJSONStream.request(
      client,
      :post,
      "/v1/sprites/#{URI.encode(name)}/services/#{URI.encode(service_name)}/stop",
      params: params,
      parser: &parse_service_event/1
    )
  end

  @doc """
  Stream service logs.

  ## Options

    * `:lines` - Number of buffered lines to include
    * `:duration` - How long to follow new logs (default server-side: `0`)
  """
  @spec logs(Sprite.t(), String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def logs(%Sprite{client: client, name: name}, service_name, opts \\ []) do
    logs_by_name(client, name, service_name, opts)
  end

  @doc """
  Stream service logs by sprite name.
  """
  @spec logs_by_name(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def logs_by_name(%Client{} = client, name, service_name, opts \\ []) when is_binary(name) do
    lines = first_present(opts, [:lines, :tail, :max_lines])
    duration = first_present(opts, [:duration, :follow, :follow_for])

    params =
      []
      |> maybe_put_param(:lines, lines)
      |> maybe_put_param(:duration, duration)

    NDJSONStream.request(
      client,
      :get,
      "/v1/sprites/#{URI.encode(name)}/services/#{URI.encode(service_name)}/logs",
      params: params,
      parser: &parse_service_event/1
    )
  end

  defp parse_service_event(event) do
    case Shapes.parse_service_log_event(event) do
      {:ok, parsed} -> StreamMessage.from_map(parsed, event)
      {:error, _reason} -> StreamMessage.from_map(event, event)
    end
  end

  defp normalize_upsert_payload(attrs) do
    %{}
    |> maybe_put_map(:cmd, Map.get(attrs, :cmd) || Map.get(attrs, "cmd"))
    |> maybe_put_map(:args, Map.get(attrs, :args) || Map.get(attrs, "args"))
    |> maybe_put_map(:needs, Map.get(attrs, :needs) || Map.get(attrs, "needs"))
    |> maybe_put_map(:http_port, Map.get(attrs, :http_port) || Map.get(attrs, "http_port"))
  end

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: params ++ [{key, value}]

  defp first_present(opts, keys) do
    Enum.find_value(keys, fn key ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end
end
