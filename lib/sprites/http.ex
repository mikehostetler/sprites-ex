defmodule Sprites.HTTP do
  @moduledoc """
  Shared HTTP request/response helpers for Sprites API calls.
  """

  alias Sprites.Error

  @type success_statuses :: Range.t() | [non_neg_integer()]

  @spec get(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def get(req, opts \\ []), do: Req.get(req, opts)

  @spec post(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def post(req, opts \\ []), do: Req.post(req, opts)

  @spec put(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def put(req, opts \\ []), do: Req.put(req, opts)

  @spec delete(Req.Request.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def delete(req, opts \\ []), do: Req.delete(req, opts)

  @spec request(Req.Request.t(), atom(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(req, method, opts \\ []) do
    Req.request(req, Keyword.merge([method: method], opts))
  end

  @spec unwrap({:ok, Req.Response.t()} | {:error, term()}, success_statuses()) ::
          {:ok, Req.Response.t()} | {:error, Error.APIError.t() | term()}
  def unwrap(response, success \\ 200..299)

  def unwrap({:ok, %{status: status} = resp}, success) do
    if success?(status, success) do
      {:ok, resp}
    else
      {:error, api_error(status, Map.get(resp, :body), Map.get(resp, :headers, []))}
    end
  end

  def unwrap({:error, reason}, _success), do: {:error, reason}

  @spec unwrap_body({:ok, Req.Response.t()} | {:error, term()}, success_statuses()) ::
          {:ok, term()} | {:error, Error.APIError.t() | term()}
  def unwrap_body(response, success \\ 200..299) do
    with {:ok, resp} <- unwrap(response, success) do
      {:ok, Map.get(resp, :body)}
    end
  end

  @spec maybe_not_found({:ok, Req.Response.t()} | {:error, term()}) ::
          :not_found | {:ok, Req.Response.t()} | {:error, Error.APIError.t() | term()}
  def maybe_not_found({:ok, %{status: 404}}), do: :not_found
  def maybe_not_found(response), do: unwrap(response)

  @spec api_error(non_neg_integer(), term(), list()) :: Error.APIError.t()
  def api_error(status, body, headers \\ []) do
    {:ok, parsed} =
      Error.parse_api_error(status, body_to_binary(body), normalize_headers(headers))

    parsed
  end

  @spec success?(non_neg_integer(), success_statuses()) :: boolean()
  def success?(status, %Range{} = range), do: status in range
  def success?(status, list) when is_list(list), do: status in list

  defp normalize_headers(headers) when is_list(headers), do: headers
  defp normalize_headers(_), do: []

  defp body_to_binary(nil), do: ""
  defp body_to_binary(body) when is_binary(body), do: body

  defp body_to_binary(body) do
    Jason.encode!(body)
  rescue
    _ -> inspect(body)
  end
end
