# MalachiMQ - AI Coding Agent Instructions

## Project Overview

MalachiMQ is a high-performance message queue built with Elixir/OTP. It features a TCP/TLS server for client connections, web dashboard, authentication, and automatic queue partitioning across CPU cores.

## Architecture

### Core Components (lib/malachimq/)
- **`application.ex`** - OTP supervisor tree entry point; starts all services in order
- **`queue.ex`** - Per-partition queue using ETS for high-throughput message storage and dispatch
- **`partition_manager.ex`** - Distributes queues across CPU cores using `erlang:phash2`
- **`consumer.ex`** - Lightweight GenServer with aggressive hibernation for memory efficiency
- **`tcp_acceptor_pool.ex` / `tcp_acceptor.ex`** - Pool of acceptors matching scheduler count; handles TCP/TLS
- **`auth.ex`** - Session-based auth with ETS-stored users and tokens; supports permissions (`:admin`, `:produce`, `:consume`)
- **`ack_manager.ex`** - Tracks pending acknowledgments; requeues on timeout/nack
- **`metrics.ex`** - ETS-based real-time metrics with atomic counters
- **`dashboard.ex`** - HTTP server serving `/`, `/metrics`, `/stream` (SSE) endpoints
- **`i18n.ex`** - Internationalization (en_US, pt_BR) using pattern matching
- **`benchmark.ex`** - Performance testing utilities for consumers and message throughput

### Data Flow
1. Client connects via TCP/TLS → `TCPAcceptor` handles auth via JSON protocol
2. Producer sends `{"action": "publish", "queue_name": "q", "payload": "..."}` 
3. `PartitionManager.get_partition/1` hashes queue name → routes to correct partition
4. `Queue` dispatches to waiting consumers or buffers in ETS
5. `Consumer` processes message, sends ack/nack to `AckManager`

### TCP/JSON Protocol

All messages are newline-delimited JSON. Responses use `"s"` for status (`"ok"` or `"err"`).

**Authentication (required first):**
```json
{"action": "auth", "username": "producer", "password": "producer123"}
→ {"s": "ok", "token": "<session_token>"}
```

**Publish message (requires `:produce` permission):**
```json
{"action": "publish", "queue_name": "orders", "payload": "...", "headers": {"priority": 1}}
→ {"s": "ok"}
```

**Subscribe to queue (requires `:consume` permission):**
```json
{"action": "subscribe", "queue_name": "orders"}
→ {"s": "ok"}
← {"queue_message": {...}}  // Messages pushed to client
```

**Shorthand publish (action optional):**
```json
{"queue_name": "orders", "payload": "..."}
→ {"s": "ok"}
```

**Error responses:**
```json
{"s": "err", "reason": "invalid_credentials|permission_denied|auth_required|invalid_request"}
```

## Developer Commands

```bash
# Development
mix deps.get          # Install dependencies
mix compile           # Compile
mix run --no-halt     # Run locally
mix test              # Run tests

# Docker
make docker-build     # Build image with version from mix.exs
make docker-run       # Run container (ports 4040, 4041)
make compose-up       # Docker Compose
make compose-logs     # Follow logs

# TLS Development
./scripts/generate-dev-certs.sh   # Generate self-signed certs in priv/cert/
```

## Code Conventions

### GenServer Patterns
- Use `{:continue, :action}` for post-init work (see `consumer.ex`)
- Return `:hibernate` from callbacks for long-idle processes
- Use `Process.flag(:message_queue_data, :off_heap)` for consumers

### ETS Usage
- Tables are `:public` with `read_concurrency: true, write_concurrency: true`
- Use `decentralized_counters: true` for hot tables
- Prefer `:ets.update_counter/4` with default tuple for atomic increments

### Error Handling
- Consumer callbacks returning `:error` or `{:error, _}` trigger nack with requeue
- Use `MalachiMQ.I18n.t/2` for all log messages

### Naming Conventions
- Queue process names: `{queue_name, partition}` tuples via Registry
- ETS tables: `String.to_atom("malachimq_#{name}_#{partition}")`

## Configuration

Configuration flows: `config/config.exs` → `config/runtime.exs` (env vars)

Key settings in `runtime.exs`:
- `MALACHIMQ_ENABLE_TLS=true` - Enable TLS (requires cert/key paths)
- `MALACHIMQ_PARTITION_MULTIPLIER` - Partitions per core (default: 100)
- `MALACHIMQ_DEFAULT_USERS` - Custom users format: `user:pass:perm1,perm2;...`

## Testing

Tests in `test/` use ExUnit. Key test files:
- `malachimq_test.exs` - Module loading checks
- `tls_config_test.exs` - TLS configuration
- `security_xss_test.exs` - XSS prevention in dashboard
- `i18n_test.exs` - Translation coverage

Run specific test: `mix test test/tls_config_test.exs`

## Dashboard & Monitoring

### HTTP Endpoints (port 4041)
- **`GET /`** - Real-time dashboard with auto-updating metrics
- **`GET /metrics`** - JSON snapshot of all queue and system metrics
- **`GET /stream`** - Server-Sent Events (SSE) for live updates

### SSE Event Format (`/stream`)
Events are pushed every 1 second (configurable via `MALACHIMQ_DASHBOARD_UPDATE_INTERVAL_MS`):
```json
data: {
  "queues": [{"queue": "orders", "processed": 1000, "acked": 950, ...}],
  "system": {"process_count": 500, "memory": {"total_mb": 128.5}}
}
```

## Benchmarking

Use `MalachiMQ.Benchmark` in IEx for performance testing:
```elixir
# Start the app
iex -S mix

# Spawn 10,000 consumers on a queue
MalachiMQ.Benchmark.spawn_consumers("test_queue", 10_000)

# Send 100,000 messages
MalachiMQ.Benchmark.send_messages("test_queue", 100_000)

# View system info (schedulers, processes, memory)
MalachiMQ.Benchmark.system_info()
```

## Adding New Features

### New Queue Operation
1. Add public function in `queue.ex` with `get_partition/1` routing
2. Handle in `handle_call/cast` with proper ETS operations
3. Expose via TCP protocol in `tcp_acceptor.ex` → `process_authenticated/4`
4. Add permission check using `Auth.has_permission?/2`

### New Metric
1. Add `increment_*` or `record_*` function in `metrics.ex`
2. Include in `get_metrics/1` return map
3. Call from appropriate module (queue, consumer, ack_manager)

### New Translation
1. Add key to `@translations` map in `i18n.ex` with both `"pt_BR"` and `"en_US"` values
2. Use `I18n.t(:key, bindings)` in code

## Contributing Conventions

### Branch Naming
- Feature branches: `feat/description` (e.g., `feat/tls-support`)
- Bug fixes: `fix/description`
- Documentation: `docs/description`

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):
```
<type>: <description>

Types: feat, fix, docs, test, refactor, chore
Examples:
  feat: add TLS support
  fix: resolve authentication bug
  docs: update README
```

### PR Requirements
- All tests must pass (`mix test`)
- Code formatted (`mix format`)
- Credo checks pass (`mix credo --strict`)
- PR title follows conventional commits format

### Version Bumping
- `feat:` → minor version bump
- `fix:` → patch version bump  
- `[major]` in title or `BREAKING CHANGE:` in body → major version bump
