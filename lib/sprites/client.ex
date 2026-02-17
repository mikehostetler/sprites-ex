defmodule Sprites.Client do
  @moduledoc """
  HTTP client for Sprites REST API operations.
  """

  alias Sprites.{HTTP, Shapes}

  @default_base_url "https://api.sprites.dev"
  @default_timeout 30_000
  @create_timeout 120_000

  defstruct [:token, :base_url, :timeout, :req, control_mode: false]

  @type t :: %__MODULE__{
          token: String.t(),
          base_url: String.t(),
          timeout: non_neg_integer(),
          req: Req.Request.t(),
          control_mode: boolean()
        }

  @doc """
  Creates a new client.

  ## Options

    * `:base_url` - API base URL (default: "https://api.sprites.dev")
    * `:timeout` - HTTP timeout in milliseconds (default: 30_000)
    * `:control_mode` - Enable control mode for multiplexed exec over a single WebSocket (default: false)
  """
  @spec new(String.t(), keyword()) :: t()
  def new(token, opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url) |> normalize_url()
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    control_mode = Keyword.get(opts, :control_mode, false)

    req =
      Req.new(
        base_url: base_url,
        headers: [{"authorization", "Bearer #{token}"}],
        receive_timeout: timeout
      )

    %__MODULE__{
      token: token,
      base_url: base_url,
      timeout: timeout,
      req: req,
      control_mode: control_mode
    }
  end

  @doc """
  Creates a new sprite.

  ## Options

    * `:config` - Sprite configuration map
    * `:url_settings` - URL settings map
  """
  @spec create_sprite(t(), String.t(), keyword()) :: {:ok, Sprites.Sprite.t()} | {:error, term()}
  def create_sprite(client, name, opts \\ []) do
    body =
      %{name: name}
      |> maybe_put(:config, Keyword.get(opts, :config))
      |> maybe_put(:url_settings, Keyword.get(opts, :url_settings))

    with {:ok, response_body} <-
           client.req
           |> HTTP.post(url: "/v1/sprites", json: body, receive_timeout: @create_timeout)
           |> HTTP.unwrap_body(),
         {:ok, sprite_body} <- normalize_sprite_body(response_body) do
      {:ok, Sprites.Sprite.new(client, name, sprite_body)}
    end
  end

  @doc """
  Deletes a sprite.
  """
  @spec delete_sprite(t(), String.t()) :: :ok | {:error, term()}
  def delete_sprite(client, name) do
    case client.req |> HTTP.delete(url: "/v1/sprites/#{URI.encode(name)}") |> HTTP.unwrap() do
      {:ok, _} ->
        :ok

      {:error, %Sprites.Error.APIError{status: 404}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists sprites.

  ## Options

    * `:prefix` - Filter by name prefix
    * `:max_results` - Maximum number of results per page
    * `:continuation_token` - Pagination token
  """
  @spec list_sprites(t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_sprites(client, opts \\ []) do
    with {:ok, %{"sprites" => sprites}} <- list_sprites_page(client, opts) do
      {:ok, sprites}
    end
  end

  @doc """
  Lists sprites and returns a normalized page payload.

  Returned shape:
    * `"sprites"` - list of sprite entries
    * `"has_more"` - boolean
    * `"next_continuation_token"` - next pagination token or nil
  """
  @spec list_sprites_page(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_sprites_page(client, opts \\ []) do
    params =
      []
      |> maybe_put_param(:prefix, Keyword.get(opts, :prefix))
      |> maybe_put_param(:max_results, Keyword.get(opts, :max_results))
      |> maybe_put_param(:continuation_token, Keyword.get(opts, :continuation_token))

    with {:ok, body} <-
           client.req
           |> HTTP.get(url: "/v1/sprites", params: params)
           |> HTTP.unwrap_body(),
         {:ok, normalized} <- normalize_sprite_page(body) do
      {:ok, normalized}
    end
  end

  @doc """
  Gets detailed information about a sprite.
  """
  @spec get_sprite(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_sprite(client, name) do
    with {:ok, body} <-
           client.req
           |> HTTP.get(url: "/v1/sprites/#{URI.encode(name)}")
           |> HTTP.unwrap_body(),
         {:ok, sprite} <- normalize_sprite_body(body) do
      {:ok, sprite}
    end
  end

  @doc """
  Triggers an upgrade for a sprite.
  """
  @spec upgrade_sprite(t(), String.t()) :: :ok | {:error, term()}
  def upgrade_sprite(client, name) do
    case client.req
         |> HTTP.post(url: "/v1/sprites/#{URI.encode(name)}/upgrade")
         |> HTTP.unwrap() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates URL settings for a sprite.
  """
  @spec update_url_settings(t(), String.t(), map()) :: :ok | {:error, term()}
  def update_url_settings(client, name, settings) do
    case update_sprite(client, name, %{url_settings: settings}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates sprite settings and returns the updated sprite payload.
  """
  @spec update_sprite(t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_sprite(client, name, settings) when is_map(settings) do
    with {:ok, body} <-
           client.req
           |> HTTP.put(url: "/v1/sprites/#{URI.encode(name)}", json: settings)
           |> HTTP.unwrap_body(),
         {:ok, sprite} <- normalize_sprite_body(body) do
      {:ok, sprite}
    end
  end

  @doc """
  Executes a command over HTTP (`POST /v1/sprites/{name}/exec`).

  This is a non-WebSocket path for environments where full-duplex streaming is
  not available.

  ## Options

    * `:path` - Explicit executable path
    * `:stdin` - Whether stdin request body should be forwarded (default: false)
    * `:stdin_data` - Request body data to forward as stdin
    * `:env` - List of `{key, value}` env vars
    * `:dir` - Working directory
  """
  @spec exec_http(t(), String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def exec_http(client, name, command, args \\ [], opts \\ []) do
    params =
      [{"cmd", command} | Enum.map(args, &{"cmd", &1})]
      |> maybe_put_param("path", Keyword.get(opts, :path))
      |> maybe_put_param("stdin", bool_param(Keyword.get(opts, :stdin, false)))
      |> maybe_put_param("dir", Keyword.get(opts, :dir))
      |> add_env_params(Keyword.get(opts, :env, []))

    request_opts =
      [
        url: "/v1/sprites/#{URI.encode(name)}/exec",
        params: params
      ]
      |> maybe_put_req_body(Keyword.get(opts, :stdin_data))

    with {:ok, body} <-
           client.req
           |> HTTP.post(request_opts)
           |> HTTP.unwrap_body() do
      {:ok, parse_exec_http_body(body)}
    end
  end

  @doc false
  @spec req(t()) :: Req.Request.t()
  def req(%__MODULE__{req: req}), do: req

  defp parse_sprite(map) when is_map(map) do
    case Shapes.parse_sprite(map) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> map
    end
  end

  defp normalize_sprite_body(%{} = body), do: {:ok, parse_sprite(body)}
  defp normalize_sprite_body(other), do: {:error, {:unexpected_response_shape, other}}

  defp normalize_sprite_page(%{"sprites" => sprites} = page) when is_list(sprites) do
    parsed_sprites = Enum.map(sprites, &parse_sprite_entry/1)

    parsed_page =
      case Shapes.parse_sprite_page(%{page | "sprites" => parsed_sprites}) do
        {:ok, parsed} -> parsed
        {:error, _reason} -> %{page | "sprites" => parsed_sprites}
      end

    {:ok,
     parsed_page
     |> Map.put_new("has_more", false)
     |> Map.put_new("next_continuation_token", nil)}
  end

  defp normalize_sprite_page(list) when is_list(list) do
    {:ok,
     %{
       "sprites" => Enum.map(list, &parse_sprite_entry/1),
       "has_more" => false,
       "next_continuation_token" => nil
     }}
  end

  defp normalize_sprite_page(other) do
    {:error, {:unexpected_response_shape, other}}
  end

  defp parse_sprite_entry(entry) when is_map(entry) do
    case Shapes.parse_sprite_entry(entry) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> entry
    end
  end

  defp parse_sprite_entry(other), do: other

  defp parse_exec_http_body(body) when is_map(body) do
    case Shapes.parse_exec_http_response(body) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> body
    end
  end

  defp parse_exec_http_body(body), do: body

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: params ++ [{key, value}]

  defp add_env_params(params, []), do: params

  defp add_env_params(params, env) do
    Enum.reduce(env, params, fn {k, v}, acc ->
      acc ++ [{"env", "#{k}=#{v}"}]
    end)
  end

  defp maybe_put_req_body(opts, nil), do: opts
  defp maybe_put_req_body(opts, data), do: Keyword.put(opts, :body, IO.iodata_to_binary(data))

  defp normalize_url(url) do
    String.trim_trailing(url, "/")
  end

  defp bool_param(true), do: "true"
  defp bool_param(false), do: "false"
end
