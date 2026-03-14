defmodule Sprites.HTTPTest do
  use ExUnit.Case, async: true

  alias Sprites.Error.APIError
  alias Sprites.HTTP

  test "unwrap accepts success range" do
    response = {:ok, %Req.Response{status: 201, body: %{"ok" => true}, headers: []}}

    assert {:ok, %Req.Response{status: 201}} = HTTP.unwrap(response, 200..299)
  end

  test "unwrap accepts explicit success status list" do
    response = {:ok, %Req.Response{status: 204, body: nil, headers: []}}

    assert {:ok, %Req.Response{status: 204}} = HTTP.unwrap(response, [200, 204])
  end

  test "unwrap converts non-success statuses into APIError" do
    response =
      {:ok,
       %Req.Response{
         status: 429,
         body: %{"error" => "rate_limited", "message" => "slow down"},
         headers: [{"retry-after", "12"}]
       }}

    assert {:error, %APIError{} = err} = HTTP.unwrap(response, 200..299)
    assert err.status == 429
    assert err.error_code == "rate_limited"
    assert err.retry_after_header == 12
  end

  test "unwrap handles malformed JSON error body" do
    response =
      {:ok, %Req.Response{status: 500, body: "<<<invalid-json>>>", headers: []}}

    assert {:error, %APIError{} = err} = HTTP.unwrap(response)
    assert err.status == 500
    assert err.message == "<<<invalid-json>>>"
  end

  test "unwrap passes through transport errors" do
    assert {:error, :timeout} = HTTP.unwrap({:error, :timeout})
  end

  test "unwrap_body returns body for successful responses" do
    response = {:ok, %Req.Response{status: 200, body: %{"value" => 42}, headers: []}}

    assert {:ok, %{"value" => 42}} = HTTP.unwrap_body(response)
  end

  test "maybe_not_found returns :not_found for 404" do
    response = {:ok, %Req.Response{status: 404, body: %{"error" => "not_found"}, headers: []}}

    assert :not_found = HTTP.maybe_not_found(response)
  end
end
