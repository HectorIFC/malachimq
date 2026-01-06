defmodule MalachiMQ.TCPAcceptor do
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  def start_link({port, opts, id, transport}) do
    GenServer.start_link(__MODULE__, {port, opts, id, transport})
  end

  @impl true
  def init({port, opts, id, transport}) do
    listen_result = 
      case transport do
        :ssl -> :ssl.listen(port, opts)
        :gen_tcp -> :gen_tcp.listen(port, opts)
      end

    case listen_result do
      {:ok, socket} ->
        Logger.info(I18n.t(:acceptor_started, id: id))
        send(self(), :accept)
        {:ok, %{socket: socket, id: id, connections: 0, idle_count: 0, transport: transport}}
      
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, %{socket: socket, idle_count: idle_count, transport: transport} = state) do
    timeout = min(100 + (idle_count * 50), 30000)

    accept_result =
      case transport do
        :ssl -> :ssl.transport_accept(socket, timeout)
        :gen_tcp -> :gen_tcp.accept(socket, timeout)
      end

    case accept_result do
      {:ok, client} ->
        client_socket = 
          if transport == :ssl do
            case :ssl.handshake(client, timeout) do
              {:ok, tls_socket} -> tls_socket
              {:error, reason} ->
                Logger.warning(I18n.t(:tls_handshake_failed, reason: inspect(reason)))
                :ssl.close(client)
                nil
            end
          else
            client
          end

        if client_socket do
          spawn_link(fn -> handle_client(client_socket, transport) end)
        end

        send(self(), :accept)
        {:noreply, %{state | connections: state.connections + 1, idle_count: 0}}

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, %{state | idle_count: min(idle_count + 1, 20)}}

      {:error, reason} ->
        Logger.error(I18n.t(:accept_error, reason: inspect(reason)))
        Process.sleep(10)
        send(self(), :accept)
        {:noreply, state}
    end
  end

  defp handle_client(socket, transport) do
    case authenticate_client(socket, transport) do
      {:ok, session} ->
        receive_loop(socket, session, transport)

      {:error, reason} ->
        send_error(socket, reason, transport)
        case transport do
          :ssl -> :ssl.close(socket)
          :gen_tcp -> :gen_tcp.close(socket)
        end
    end
  end

  defp authenticate_client(socket, transport) do
    set_socket_opts(socket, transport, active: false)
    recv_timeout = Application.get_env(:malachimq, :auth_timeout_ms, 10_000)

    case recv_data(socket, transport, 0, recv_timeout) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, %{"action" => "auth", "username" => username, "password" => password}} ->
            case MalachiMQ.Auth.authenticate(username, password) do
              {:ok, token} ->
                case MalachiMQ.Auth.validate_token(token) do
                  {:ok, session} ->
                    response = Jason.encode!(%{"s" => "ok", "token" => token})
                    send_data(socket, response <> "\n", transport)
                    {:ok, session}

                  {:error, _} ->
                    {:error, :invalid_token}
                end

              {:error, _reason} ->
                {:error, :invalid_credentials}
            end

          _ ->
            {:error, :auth_required}
        end

      {:error, _} ->
        {:error, :connection_error}
    end
  end

  defp receive_loop(socket, session, transport) do
    recv_timeout = Application.get_env(:malachimq, :tcp_recv_timeout, 30_000)

    case recv_data(socket, transport, 0, recv_timeout) do
      {:ok, data} ->
        process_authenticated(socket, data, session, transport)
        receive_loop(socket, session, transport)

      {:error, _} ->
        case transport do
          :ssl -> :ssl.close(socket)
          :gen_tcp -> :gen_tcp.close(socket)
        end
    end
  end

  @compile {:inline, process_authenticated: 4}
  defp process_authenticated(socket, data, session, transport) do
    case Jason.decode(data) do
      {:ok, %{"action" => "publish", "queue_name" => q, "payload" => p} = msg} ->
        if MalachiMQ.Auth.has_permission?(session.permissions, :produce) do
          h = Map.get(msg, "headers", %{})
          MalachiMQ.Queue.enqueue(q, p, h)
          send_data(socket, ~s({"s":"ok"}\n), transport)
        else
          Logger.warning(I18n.t(:permission_denied, username: session.username, action: "publish"))
          send_data(socket, ~s({"s":"err","reason":"permission_denied"}\n), transport)
        end

      {:ok, %{"action" => "subscribe", "queue_name" => q}} ->
        if MalachiMQ.Auth.has_permission?(session.permissions, :consume) do
          MalachiMQ.Queue.subscribe(q, self())
          send_data(socket, ~s({"s":"ok"}\n), transport)
        else
          Logger.warning(I18n.t(:permission_denied, username: session.username, action: "subscribe"))
          send_data(socket, ~s({"s":"err","reason":"permission_denied"}\n), transport)
        end

      {:ok, %{"queue_name" => q, "payload" => p} = msg} ->
        if MalachiMQ.Auth.has_permission?(session.permissions, :produce) do
          h = Map.get(msg, "headers", %{})
          MalachiMQ.Queue.enqueue(q, p, h)
          send_data(socket, ~s({"s":"ok"}\n), transport)
        else
          send_data(socket, ~s({"s":"err","reason":"permission_denied"}\n), transport)
        end

      _ ->
        send_data(socket, ~s({"s":"err","reason":"invalid_request"}\n), transport)
    end
  end

  defp send_error(socket, :invalid_credentials, transport) do
    send_data(socket, ~s({"s":"err","reason":"invalid_credentials"}\n), transport)
  end

  defp send_error(socket, :auth_required, transport) do
    send_data(socket, ~s({"s":"err","reason":"auth_required"}\n), transport)
  end

  defp send_error(socket, _, transport) do
    send_data(socket, ~s({"s":"err","reason":"error"}\n), transport)
  end

  # Socket helper functions
  defp recv_data(socket, :ssl, length, timeout), do: :ssl.recv(socket, length, timeout)
  defp recv_data(socket, :gen_tcp, length, timeout), do: :gen_tcp.recv(socket, length, timeout)

  defp send_data(socket, data, :ssl), do: :ssl.send(socket, data)
  defp send_data(socket, data, :gen_tcp), do: :gen_tcp.send(socket, data)

  defp set_socket_opts(socket, :ssl, opts), do: :ssl.setopts(socket, opts)
  defp set_socket_opts(socket, :gen_tcp, opts), do: :inet.setopts(socket, opts)
end
