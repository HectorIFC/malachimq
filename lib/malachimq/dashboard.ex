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
    queue_metrics = MalachiMQ.Metrics.get_all_metrics()

    # Enrich each queue with producer/consumer IPs
    enriched_queues =
      Enum.map(queue_metrics, fn queue ->
        producers = MalachiMQ.ConnectionRegistry.list_producers_by_queue(queue.queue)
        consumers = MalachiMQ.ConnectionRegistry.list_consumers_by_queue(queue.queue)

        Map.merge(queue, %{
          producer_ips: producers,
          consumer_ips: consumers
        })
      end)

    channel_metrics = MalachiMQ.Metrics.get_all_channel_metrics()

    # Enrich each channel with subscriber IPs
    enriched_channels =
      Enum.map(channel_metrics, fn channel ->
        subscribers = MalachiMQ.ConnectionRegistry.list_subscribers_by_channel(channel.channel)

        Map.merge(channel, %{
          subscriber_ips: subscribers
        })
      end)

    metrics = %{
      queues: enriched_queues,
      channels: enriched_channels,
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
    queue_metrics = MalachiMQ.Metrics.get_all_metrics()

    # Enrich each queue with producer/consumer IPs
    enriched_queues =
      Enum.map(queue_metrics, fn queue ->
        producers = MalachiMQ.ConnectionRegistry.list_producers_by_queue(queue.queue)
        consumers = MalachiMQ.ConnectionRegistry.list_consumers_by_queue(queue.queue)

        Map.merge(queue, %{
          producer_ips: producers,
          consumer_ips: consumers
        })
      end)

    channel_metrics = MalachiMQ.Metrics.get_all_channel_metrics()

    # Enrich each channel with subscriber IPs
    enriched_channels =
      Enum.map(channel_metrics, fn channel ->
        subscribers = MalachiMQ.ConnectionRegistry.list_subscribers_by_channel(channel.channel)

        Map.merge(channel, %{
          subscriber_ips: subscribers
        })
      end)

    metrics = %{
      queues: enriched_queues,
      channels: enriched_channels,
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
        h2 { color: #00d9ff; margin-bottom: 15px; font-size: 1.2em; }
        .card {
          background: #1a1f3a;
          border: 1px solid #2a3f5f;
          border-radius: 8px;
          padding: 20px;
          margin-bottom: 20px;
        }
        .metric { display: flex; justify-content: space-between; padding: 8px 0; }
        .metric-value { color: #00ff88; font-family: monospace; }
        .grid-container {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
          gap: 20px;
          margin-bottom: 20px;
        }
        .connection-list {
          max-height: 200px;
          overflow-y: auto;
          margin-top: 10px;
          padding: 5px;
        }
        .connection-item {
          background: #0f1428;
          border-left: 3px solid #00d9ff;
          padding: 8px;
          margin-bottom: 6px;
          border-radius: 4px;
          font-size: 0.85em;
        }
        .connection-item .ip {
          color: #00ff88;
          font-family: monospace;
          font-weight: bold;
          font-size: 0.9em;
        }
        .connection-item .time {
          color: #888;
          font-size: 0.8em;
        }
        .pagination {
          display: flex;
          justify-content: center;
          gap: 10px;
          margin-top: 15px;
        }
        .pagination button {
          background: #2a3f5f;
          border: 1px solid #3a4f6f;
          color: #e0e0e0;
          padding: 8px 15px;
          border-radius: 5px;
          cursor: pointer;
          font-size: 0.9em;
        }
        .pagination button:hover:not(:disabled) {
          background: #3a4f6f;
        }
        .pagination button:disabled {
          opacity: 0.5;
          cursor: not-allowed;
        }
        .pagination .page-info {
          display: flex;
          align-items: center;
          color: #888;
        }
        .empty-state {
          text-align: center;
          color: #666;
          padding: 30px;
          font-style: italic;
        }
        .queue-card {
          background: #1a1f3a;
          border: 1px solid #2a3f5f;
          border-left: 4px solid #00d9ff;
          border-radius: 8px;
          padding: 15px;
          margin-bottom: 15px;
        }
        .channel-card {
          background: #1a1f3a;
          border: 1px solid #2a3f5f;
          border-left: 4px solid #a855f7;
          border-radius: 8px;
          padding: 15px;
          margin-bottom: 15px;
        }
        .queue-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 12px;
          padding-bottom: 12px;
          border-bottom: 1px solid #2a3f5f;
        }
        .queue-name {
          color: #00ff88;
          font-size: 1.1em;
          font-weight: bold;
          font-family: monospace;
        }
        .queue-metrics {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
          gap: 10px;
          margin-bottom: 15px;
          font-size: 0.9em;
        }
        .queue-metric-item {
          padding: 5px;
        }
        .connections-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 15px;
          margin-top: 12px;
        }
        .connection-section {
          background: #0f1428;
          border-radius: 6px;
          padding: 10px;
        }
        .connection-section h3 {
          color: #00d9ff;
          font-size: 0.95em;
          margin-bottom: 8px;
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .connection-count {
          background: #2a3f5f;
          color: #00ff88;
          padding: 2px 8px;
          border-radius: 12px;
          font-size: 0.85em;
        }
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

      <div class="card">
        <h2>Channels</h2>
        <div id="channels">Loading...</div>
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

        // Pagination state - one state per queue
        const queuePaginationState = {};

        function formatTime(timestamp) {
          const now = Date.now();
          const diff = now - timestamp;
          const seconds = Math.floor(diff / 1000);
          const minutes = Math.floor(seconds / 60);
          const hours = Math.floor(minutes / 60);
          const days = Math.floor(hours / 24);

          if (days > 0) return `${days}d ago`;
          if (hours > 0) return `${hours}h ago`;
          if (minutes > 0) return `${minutes}m ago`;
          return `${seconds}s ago`;
        }

        function renderConnectionList(connections, type, queueName) {
          if (!queuePaginationState[queueName]) {
            queuePaginationState[queueName] = {
              producerPage: 1,
              consumerPage: 1,
              subscriberPage: 1,
              perPage: 10
            };
          }

          const page = type === 'producer' 
            ? queuePaginationState[queueName].producerPage 
            : type === 'consumer'
            ? queuePaginationState[queueName].consumerPage
            : queuePaginationState[queueName].subscriberPage;
          const perPage = queuePaginationState[queueName].perPage;
          const start = (page - 1) * perPage;
          const end = start + perPage;
          const pageData = connections.slice(start, end);
          const totalPages = Math.ceil(connections.length / perPage);

          if (connections.length === 0) {
            return `
              <div class="connection-section">
                <h3>${type === 'producer' ? '📤 Producers' : type === 'consumer' ? '📥 Consumers' : '📡 Subscribers'} <span class="connection-count">0</span></h3>
                <div class="empty-state" style="padding: 15px; font-size: 0.85em;">No ${type}s</div>
              </div>
            `;
          }

          const itemsHtml = pageData.map(item => {
            const time = formatTime(item.connected_at);
            return `
              <div class="connection-item">
                <div class="ip">${escapeHtml(item.ip)}</div>
                <div class="time">Connected ${time}</div>
              </div>
            `;
          }).join('');

          const paginationHtml = totalPages > 1 ? `
            <div class="pagination">
              <button onclick="changeQueuePage('${escapeHtml(queueName)}', '${type}', -1)" ${page <= 1 ? 'disabled' : ''}>← Prev</button>
              <span class="page-info">Page ${page} of ${totalPages}</span>
              <button onclick="changeQueuePage('${escapeHtml(queueName)}', '${type}', 1)" ${page >= totalPages ? 'disabled' : ''}>Next →</button>
            </div>
          ` : '';

          return `
            <div class="connection-section">
              <h3>${type === 'producer' ? '📤 Producers' : type === 'consumer' ? '📥 Consumers' : '📡 Subscribers'} <span class="connection-count">${connections.length}</span></h3>
              <div class="connection-list">
                ${itemsHtml}
              </div>
              ${paginationHtml}
            </div>
          `;
        }

        function changeQueuePage(queueName, type, direction) {
          if (!queuePaginationState[queueName]) return;

          const currentPage = type === 'producer' 
            ? queuePaginationState[queueName].producerPage 
            : type === 'consumer'
            ? queuePaginationState[queueName].consumerPage
            : queuePaginationState[queueName].subscriberPage;
          const newPage = currentPage + direction;

          if (newPage >= 1) {
            if (type === 'producer') {
              queuePaginationState[queueName].producerPage = newPage;
            } else if (type === 'consumer') {
              queuePaginationState[queueName].consumerPage = newPage;
            } else {
              queuePaginationState[queueName].subscriberPage = newPage;
            }
            // Force re-render by triggering update
            const lastData = window.lastMetricsData;
            if (lastData) {
              renderQueues(lastData.queues);
              renderChannels(lastData.channels);
            }
          }
        }

        function renderQueues(queues) {
          if (!queues || queues.length === 0) {
            document.getElementById('queues').innerHTML = '<div class="empty-state">No queues</div>';
            return;
          }

          const queuesHtml = queues.map(q => {
            const producers = q.producer_ips || [];
            const consumers = q.consumer_ips || [];

            const producerList = renderConnectionList(producers, 'producer', q.queue);
            const consumerList = renderConnectionList(consumers, 'consumer', q.queue);

            return `
              <div class="queue-card">
                <div class="queue-header">
                  <div class="queue-name">${escapeHtml(q.queue)}</div>
                </div>
                
                <div class="queue-metrics">
                  <div class="queue-metric-item">
                    <span style="color: #888;">Producers:</span> <span style="color: #00ff88;">${q.queue_stats.producers || 0}</span>
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #888;">Consumers:</span> <span style="color: #00ff88;">${q.queue_stats.consumers || 0}</span>
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #00ff88;">✓ Acked:</span> ${q.acked || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #ff6b6b;">✗ Nacked:</span> ${q.nacked || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #ffd93d;">⏳ Pending:</span> ${q.pending_ack || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #6bcfff;">↻ Retried:</span> ${q.retried || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #ff4757;">☠ DLQ:</span> ${q.dead_lettered || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #888;">Processed:</span> ${q.processed}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #888;">Buffered:</span> ${q.queue_stats.buffered}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #888;">Latency:</span> ${q.latency_us.avg ? (q.latency_us.avg/1000).toFixed(2) + 'ms' : '-'}
                  </div>
                </div>

                <div class="connections-grid">
                  ${producerList}
                  ${consumerList}
                </div>
              </div>
            `;
          }).join('');

          document.getElementById('queues').innerHTML = queuesHtml;
        }

        function renderChannels(channels) {
          if (!channels || channels.length === 0) {
            document.getElementById('channels').innerHTML = '<div class="empty-state">No channels</div>';
            return;
          }

          const channelsHtml = channels.map(c => {
            const subscribers = c.subscriber_ips || [];
            const subscriberList = renderConnectionList(subscribers, 'subscriber', c.channel);
            
            // Calculate delivery and discard rates
            const deliveryRate = c.published > 0 ? ((c.delivered / c.published) * 100).toFixed(2) : '0.00';
            const discardRate = c.published > 0 ? ((c.dropped / c.published) * 100).toFixed(2) : '0.00';

            return `
              <div class="channel-card">
                <div class="queue-header">
                  <div class="queue-name">${escapeHtml(c.channel)}</div>
                </div>
                
                <div class="queue-metrics">
                  <div class="queue-metric-item">
                    <span style="color: #888;">Subscribers:</span> <span style="color: #00ff88;">${c.subscribers || 0}</span>
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #888;">Published:</span> ${c.published || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #00ff88;">✓ Delivered:</span> ${c.delivered || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #ff6b6b;">✗ Dropped:</span> ${c.dropped || 0}
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #a855f7;">📊 Delivery Rate:</span> ${deliveryRate}%
                  </div>
                  <div class="queue-metric-item">
                    <span style="color: #ff4757;">📉 Discard Rate:</span> ${discardRate}%
                  </div>
                </div>

                ${subscribers.length > 0 ? `
                  <div style="margin-top: 12px;">
                    ${subscriberList}
                  </div>
                ` : ''}
              </div>
            `;
          }).join('');

          document.getElementById('channels').innerHTML = channelsHtml;
        }

        const source = new EventSource('/stream');
        source.onmessage = (event) => {
          const data = JSON.parse(event.data);
          window.lastMetricsData = data;
          
          document.getElementById('processes').textContent = data.system.process_count;
          document.getElementById('memory').textContent = data.system.memory.total_mb.toFixed(2) + ' MB';

          renderQueues(data.queues);
          renderChannels(data.channels || []);
        };
      </script>
    </body>
    </html>
    """
  end
end
