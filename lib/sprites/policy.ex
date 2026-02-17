defmodule Sprites.Policy do
  @moduledoc """
  Network policy management for sprites.
  """

  alias Sprites.{Client, Sprite, HTTP, Shapes}

  defmodule Rule do
    @moduledoc """
    Network policy rule.

    ## Fields

      * `:domain` - Domain to match (e.g., "example.com")
      * `:action` - Action to take: "allow" or "deny"
      * `:include` - Optional include pattern for wildcard matching
      * `:raw` - Original API response map
    """
    @type t :: %__MODULE__{
            domain: String.t() | nil,
            action: String.t() | nil,
            include: String.t() | nil,
            raw: map() | nil
          }

    defstruct [:domain, :action, :include, :raw]

    @doc """
    Creates a rule from a map.
    """
    @spec from_map(map()) :: t()
    def from_map(map) when is_map(map) do
      parsed =
        case Shapes.parse_policy_rule(map) do
          {:ok, parsed} -> parsed
          {:error, _reason} -> map
        end

      %__MODULE__{
        domain: Map.get(parsed, "domain") || Map.get(parsed, :domain),
        action: Map.get(parsed, "action") || Map.get(parsed, :action),
        include: Map.get(parsed, "include") || Map.get(parsed, :include),
        raw: map
      }
    end

    @doc """
    Converts a rule to a map for JSON encoding.
    """
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = rule) do
      %{}
      |> maybe_put(:domain, rule.domain)
      |> maybe_put(:action, rule.action)
      |> maybe_put(:include, rule.include)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  @doc """
  Network policy containing a list of rules.

  ## Fields

    * `:rules` - List of `Sprites.Policy.Rule` structs
    * `:raw` - Original API response map
  """
  @type t :: %__MODULE__{rules: [Rule.t()], raw: map() | nil}

  defstruct rules: [], raw: nil

  @doc """
  Creates a network policy from a map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    parsed =
      case Shapes.parse_policy(map) do
        {:ok, parsed} -> parsed
        {:error, _reason} -> map
      end

    rules =
      (Map.get(parsed, "rules") || Map.get(parsed, :rules) || [])
      |> Enum.map(&Rule.from_map/1)

    %__MODULE__{rules: rules, raw: map}
  end

  @doc """
  Converts a network policy to a map for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{rules: rules}) do
    %{rules: Enum.map(rules, &Rule.to_map/1)}
  end

  @doc """
  Gets the current network policy for a sprite.

  ## Examples

      {:ok, policy} = Sprites.Policy.get(sprite)
  """
  @spec get(Sprite.t()) :: {:ok, t()} | {:error, term()}
  def get(%Sprite{client: client, name: name}) do
    get_by_name(client, name)
  end

  @doc """
  Gets the current network policy for a sprite by name.
  """
  @spec get_by_name(Client.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def get_by_name(%Client{} = client, name) when is_binary(name) do
    with {:ok, body} <-
           client.req
           |> HTTP.get(url: "/v1/sprites/#{URI.encode(name)}/policy/network")
           |> HTTP.unwrap_body() do
      {:ok, from_map(body)}
    end
  end

  @doc """
  Updates the network policy for a sprite.

  ## Examples

      policy = %Sprites.Policy{
        rules: [
          %Sprites.Policy.Rule{domain: "example.com", action: "allow"},
          %Sprites.Policy.Rule{domain: "blocked.com", action: "deny"}
        ]
      }
      :ok = Sprites.Policy.update(sprite, policy)
  """
  @spec update(Sprite.t(), t()) :: :ok | {:error, term()}
  def update(%Sprite{client: client, name: name}, %__MODULE__{} = policy) do
    update_by_name(client, name, policy)
  end

  @doc """
  Updates the network policy for a sprite by name.
  """
  @spec update_by_name(Client.t(), String.t(), t()) :: :ok | {:error, term()}
  def update_by_name(%Client{} = client, name, %__MODULE__{} = policy) when is_binary(name) do
    body = to_map(policy)

    case client.req
         |> HTTP.post(url: "/v1/sprites/#{URI.encode(name)}/policy/network", json: body)
         |> HTTP.unwrap(200..299) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
