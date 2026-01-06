defmodule MalachiMQ.Dashboard do
  use GenServer
  require Logger
  alias MalachiMQ.I18n

  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  @impl true
  def init(port) do
    opts = [:binary, packet: :http, active: false, reuseaddr: true]

    case :gen_tcp.listen(port, opts) do
      {:ok, socket} ->
        Logger.info(I18n.t(:dashboard_started, port: port))
        send(self(), :accept)
        {:ok, %{socket: socket, port: port}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, %{socket: socket} = state) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        spawn(fn -> handle_http(client) end)
        send(self(), :accept)
        {:noreply, state}

      {:error, _} ->
        send(self(), :accept)
        {:noreply, state}
    end
  end

  defp handle_http(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, {:http_request, method, {:abs_path, path}, _version}} ->
        consume_headers(socket)
        path_string = to_string(path)
        handle_route(socket, %{method: method, path: path_string})

      {:ok, {:http_request, method, :*, _version}} ->
        consume_headers(socket)
        handle_route(socket, %{method: method, path: "*"})

      {:ok, _other} ->
        :gen_tcp.close(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp consume_headers(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, :http_eoh} ->
        :ok

      {:ok, {:http_header, _, _name, _, _value}} ->
        consume_headers(socket)

      _ ->
        :ok
    end
  end

  defp handle_route(socket, %{method: :GET, path: "/"}), do: serve_html(socket)
  defp handle_route(socket, %{method: :GET, path: "/metrics"}), do: serve_metrics(socket)
  defp handle_route(socket, %{method: :GET, path: "/stream"}), do: serve_sse(socket)
  defp handle_route(socket, _), do: serve_404(socket)

  defp serve_html(socket) do
    html = dashboard_html()

    response = """
    HTTP/1.1 200 OK\r
    Content-Type: text/html; charset=utf-8\r
    Content-Length: #{byte_size(html)}\r
    \r
    #{html}
    """

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp serve_metrics(socket) do
    metrics = %{
      queues: MalachiMQ.Metrics.get_all_metrics(),
      system: MalachiMQ.Metrics.get_system_metrics()
    }

    json = Jason.encode!(metrics)

    response = """
    HTTP/1.1 200 OK\r
    Content-Type: application/json\r
    Access-Control-Allow-Origin: *\r
    Content-Length: #{byte_size(json)}\r
    \r
    #{json}
    """

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp serve_sse(socket) do
    response = """
    HTTP/1.1 200 OK\r
    Content-Type: text/event-stream\r
    Cache-Control: no-cache\r
    Connection: keep-alive\r
    Access-Control-Allow-Origin: *\r
    \r
    """

    :gen_tcp.send(socket, response)
    :inet.setopts(socket, packet: :raw)

    stream_metrics(socket)
  end

  defp stream_metrics(socket) do
    metrics = %{
      queues: MalachiMQ.Metrics.get_all_metrics(),
      system: MalachiMQ.Metrics.get_system_metrics()
    }

    json = Jason.encode!(metrics)
    event = "data: #{json}\n\n"

    update_interval = Application.get_env(:malachimq, :dashboard_update_interval_ms, 1000)

    case :gen_tcp.send(socket, event) do
      :ok ->
        Process.sleep(update_interval)
        stream_metrics(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp serve_404(socket) do
    response = """
    HTTP/1.1 404 Not Found\r
    Content-Type: text/plain\r
    Content-Length: 9\r
    \r
    Not Found
    """

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp dashboard_html do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>MalachiMQ Dashboard</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, sans-serif;
          background: #0a0e27;
          color: #e0e0e0;
          padding: 20px;
        }
        h1 { color: #00d9ff; margin-bottom: 20px; }
        .card {
          background: #1a1f3a;
          border: 1px solid #2a3f5f;
          border-radius: 8px;
          padding: 20px;
          margin-bottom: 20px;
        }
        .metric { display: flex; justify-content: space-between; padding: 8px 0; }
        .metric-value { color: #00ff88; font-family: monospace; }
      </style>
    </head>
    <body>
      <h1>🚀 MalachiMQ Dashboard</h1>
      <div class="card">
        <h2>System Status</h2>
        <div class="metric">
          <span>Processes:</span>
          <span class="metric-value" id="processes">-</span>
        </div>
        <div class="metric">
          <span>Memory:</span>
          <span class="metric-value" id="memory">-</span>
        </div>
      </div>
      <div class="card">
        <h2>Queues</h2>
        <div id="queues">Loading...</div>
      </div>
      <script>
        // HTML escape function to prevent XSS attacks
        function escapeHtml(unsafe) {
          return unsafe
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
        }

        const source = new EventSource('/stream');
        source.onmessage = (event) => {
          const data = JSON.parse(event.data);
          document.getElementById('processes').textContent = data.system.process_count;
          document.getElementById('memory').textContent = data.system.memory.total_mb.toFixed(2) + ' MB';

          const queuesHtml = data.queues.map(q =>
            `<div style="padding: 10px; border-left: 3px solid #00d9ff; margin: 10px 0;">
              <strong>${escapeHtml(q.queue)}</strong><br>
              <span style="color: #888;">Consumers:</span> ${q.queue_stats.consumers} |
              <span style="color: #00ff88;">✓ Acked:</span> ${q.acked || 0} |
              <span style="color: #ff6b6b;">✗ Nacked:</span> ${q.nacked || 0} |
              <span style="color: #ffd93d;">⏳ Pending:</span> ${q.pending_ack || 0} |
              <span style="color: #6bcfff;">↻ Retried:</span> ${q.retried || 0} |
              <span style="color: #ff4757;">☠ DLQ:</span> ${q.dead_lettered || 0}<br>
              <span style="color: #888;">Processed:</span> ${q.processed} |
              <span style="color: #888;">Buffered:</span> ${q.queue_stats.buffered} |
              <span style="color: #888;">Latency:</span> ${q.latency_us.avg ? (q.latency_us.avg/1000).toFixed(2) + 'ms' : '-'}
            </div>`
          ).join('');

          document.getElementById('queues').innerHTML = queuesHtml || 'No queues';
        };
      </script>
    </body>
    </html>
    """
  end
end
