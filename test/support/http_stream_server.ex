defmodule Sprites.TestHTTPServer do
  @moduledoc false

  @type server :: %{port: non_neg_integer(), pid: pid()}

  @spec start_once((:gen_tcp.socket(), binary() -> any())) :: {:ok, server()}
  def start_once(handler) when is_function(handler, 2) do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(listener)

    pid =
      spawn_link(fn ->
        case :gen_tcp.accept(listener, 5_000) do
          {:ok, socket} ->
            request = read_request(socket)
            handler.(socket, request)
            :gen_tcp.close(socket)

          {:error, _reason} ->
            :ok
        end

        :gen_tcp.close(listener)
      end)

    {:ok, %{port: port, pid: pid}}
  end

  @spec send_chunked(:gen_tcp.socket(), String.t(), [binary()]) :: :ok | {:error, term()}
  def send_chunked(socket, content_type, chunks) do
    headers = [
      "HTTP/1.1 200 OK",
      "Content-Type: #{content_type}",
      "Transfer-Encoding: chunked",
      "Connection: close",
      "",
      ""
    ]

    with :ok <- :gen_tcp.send(socket, Enum.join(headers, "\r\n")),
         :ok <- send_chunks(socket, chunks),
         :ok <- :gen_tcp.send(socket, "0\r\n\r\n") do
      :ok
    end
  end

  @spec send_json(:gen_tcp.socket(), non_neg_integer(), map()) :: :ok | {:error, term()}
  def send_json(socket, status, body) do
    body = Jason.encode!(body)
    send_response(socket, status, "application/json", body)
  end

  @spec send_text(:gen_tcp.socket(), non_neg_integer(), binary()) :: :ok | {:error, term()}
  def send_text(socket, status, body) do
    send_response(socket, status, "text/plain", body)
  end

  @spec read_request(:gen_tcp.socket()) :: binary()
  def read_request(socket) do
    do_read_request(socket, "")
  end

  defp do_read_request(socket, acc) do
    if String.contains?(acc, "\r\n\r\n") do
      acc
    else
      case :gen_tcp.recv(socket, 0, 2_000) do
        {:ok, data} -> do_read_request(socket, acc <> data)
        {:error, _reason} -> acc
      end
    end
  end

  defp send_chunks(_socket, []), do: :ok

  defp send_chunks(socket, [chunk | rest]) do
    encoded_size = chunk |> byte_size() |> Integer.to_string(16)

    with :ok <- :gen_tcp.send(socket, encoded_size <> "\r\n" <> chunk <> "\r\n") do
      send_chunks(socket, rest)
    end
  end

  defp send_response(socket, status, content_type, body) do
    reason = status_reason(status)

    headers = [
      "HTTP/1.1 #{status} #{reason}",
      "Content-Type: #{content_type}",
      "Content-Length: #{byte_size(body)}",
      "Connection: close",
      "",
      ""
    ]

    :gen_tcp.send(socket, Enum.join(headers, "\r\n") <> body)
  end

  defp status_reason(200), do: "OK"
  defp status_reason(201), do: "Created"
  defp status_reason(400), do: "Bad Request"
  defp status_reason(401), do: "Unauthorized"
  defp status_reason(404), do: "Not Found"
  defp status_reason(500), do: "Internal Server Error"
  defp status_reason(_), do: "OK"
end
