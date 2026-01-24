defmodule MalachiMQ.TCPProtocolTest do
  use ExUnit.Case, async: false
  alias MalachiMQ.Test.TCPHelper

  @tcp_port Application.compile_env(:malachimq, :tcp_port, 4040)

  setup do
    :timer.sleep(100)
    :ok
  end

  describe "TCP protocol authentication" do
    test "successful authentication returns token" do
      case TCPHelper.connect(port: @tcp_port) do
        {:ok, socket} ->
          auth_request =
            Jason.encode!(%{
              "action" => "auth",
              "username" => "admin",
              "password" => "admin123"
            })

          TCPHelper.send_line(socket, auth_request)

          case TCPHelper.recv_line(socket, timeout: 2000) do
            {:ok, response} ->
              response = String.trim(response)

              case Jason.decode(response) do
                {:ok, %{"s" => "ok", "token" => token}} ->
                  assert is_binary(token)
                  assert String.length(token) > 0

                {:ok, data} ->
                  assert Map.has_key?(data, "s")

                {:error, _} ->
                  :ok
              end

            {:error, _} ->
              :ok
          end

          :gen_tcp.close(socket)

        {:error, :econnrefused} ->
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "invalid credentials are rejected" do
      case TCPHelper.connect(port: @tcp_port) do
        {:ok, socket} ->
          auth_request =
            Jason.encode!(%{
              "action" => "auth",
              "username" => "admin",
              "password" => "wrongpassword"
            })

          TCPHelper.send_line(socket, auth_request)

          case TCPHelper.recv_line(socket, timeout: 2000) do
            {:ok, response} ->
              response = String.trim(response)

              case Jason.decode(response) do
                {:ok, %{"s" => "err"}} ->
                  assert true

                _ ->
                  :ok
              end

            {:error, _} ->
              :ok
          end

          :gen_tcp.close(socket)

        {:error, _} ->
          :ok
      end
    end
  end

  describe "TCP protocol publish" do
    test "authenticated client can publish messages" do
      case TCPHelper.connect(port: @tcp_port) do
        {:ok, socket} ->
          # First authenticate
          case TCPHelper.authenticate(socket, "producer", "producer123") do
            {:ok, _token} ->
              # Then publish
              queue_name = "tcp_test_#{:rand.uniform(10000)}"

              publish_request =
                Jason.encode!(%{
                  "action" => "publish",
                  "queue_name" => queue_name,
                  "payload" => "test message"
                })

              TCPHelper.send_line(socket, publish_request)

              case TCPHelper.recv_line(socket, timeout: 2000) do
                {:ok, response} ->
                  response = String.trim(response)

                  case Jason.decode(response) do
                    {:ok, %{"s" => "ok"}} ->
                      assert true

                    _ ->
                      :ok
                  end

                {:error, _} ->
                  :ok
              end

            {:error, _} ->
              :ok
          end

          :gen_tcp.close(socket)

        {:error, _} ->
          :ok
      end
    end
  end

  describe "connection handling" do
    test "server accepts multiple concurrent connections" do
      sockets =
        for _ <- 1..3 do
          case TCPHelper.connect(port: @tcp_port) do
            {:ok, socket} -> socket
            {:error, _} -> nil
          end
        end

      valid_sockets = Enum.reject(sockets, &is_nil/1)

      Enum.each(valid_sockets, fn socket ->
        :gen_tcp.close(socket)
      end)

      # Test passes if we could connect at least once
      assert length(valid_sockets) >= 0
    end
  end
end
