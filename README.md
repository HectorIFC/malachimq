# MalachiMQ

High-performance message queue system built with Elixir/OTP.

[![Docker Image](https://img.shields.io/docker/v/hectorcorrea81/malachimq?label=Docker%20Hub)](https://hub.docker.com/r/hectorcorrea81/malachimq)
[![Build Status](https://github.com/hectorcorrea81/malachimq/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/hectorcorrea81/malachimq/actions)

## 🚀 Quick Start with Docker

### Pull and Run

```bash
docker pull hectorcorrea81/malachimq:latest

docker run -d \
  --name malachimq \
  -p 4040:4040 \
  -p 4041:4041 \
  -e MALACHIMQ_ADMIN_PASS=your_secure_password \
  hectorcorrea81/malachimq:latest
```

### Using Docker Compose

```bash
git clone https://github.com/hectorcorrea81/malachimq.git
cd malachimq
docker-compose up -d
```

Access the dashboard at: http://localhost:4041

## 📦 Ports

| Port | Description |
|------|-------------|
| 4040 | TCP Message Queue |
| 4041 | Web Dashboard |

## 🔐 Authentication

MalachiMQ requires authentication for all producers and consumers.

### Default Users

| Username | Password | Permissions |
|----------|----------|-------------|
| admin | admin123 | Full access |
| producer | producer123 | Produce only |
| consumer | consumer123 | Consume only |
| app | app123 | Produce & Consume |

> ⚠️ **Important**: Change default passwords in production!

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MALACHIMQ_TCP_PORT` | 4040 | TCP server port |
| `MALACHIMQ_DASHBOARD_PORT` | 4041 | Dashboard port |
| `MALACHIMQ_LOCALE` | en_US | Language (en_US, pt_BR) |
| `MALACHIMQ_ADMIN_PASS` | admin123 | Admin password |
| `MALACHIMQ_PRODUCER_PASS` | producer123 | Producer password |
| `MALACHIMQ_CONSUMER_PASS` | consumer123 | Consumer password |
| `MALACHIMQ_APP_PASS` | app123 | App password |
| `MALACHIMQ_SESSION_TIMEOUT_MS` | 3600000 | Session timeout (1h) |

### Custom Users

```bash
docker run -d \
  -e MALACHIMQ_DEFAULT_USERS="user1:pass1:produce,consume;user2:pass2:admin" \
  hectorcorrea81/malachimq:latest
```

Format: `username:password:permission1,permission2;...`

Permissions: `admin`, `produce`, `consume`

## 📡 Client Example (Node.js)

```javascript
const net = require('net');

const client = net.createConnection(4040, 'localhost', () => {
  client.write(JSON.stringify({
    action: 'auth',
    username: 'producer',
    password: 'producer123'
  }) + '\n');
});

client.on('data', (data) => {
  const response = JSON.parse(data.toString().trim());
  
  if (response.token) {
    client.write(JSON.stringify({
      action: 'publish',
      queue_name: 'my-queue',
      payload: { hello: 'world' },
      headers: {}
    }) + '\n');
  }
});
```

### Using the Producer Script

```bash
cd scripts
npm install

MALACHIMQ_USER=producer MALACHIMQ_PASS=producer123 node producer.js
node producer.js 100
node producer.js --continuous
node producer.js 1000 --fast
```

## 🛠️ Development

### Prerequisites

- Elixir 1.16+
- Erlang/OTP 26+

### Run Locally

```bash
mix deps.get
mix run --no-halt
```

### Run Tests

```bash
mix test
```

### Build Docker Image Locally

```bash
make docker-build
make docker-run
```

### Available Make Commands

```bash
make build          # Install deps and compile
make run            # Run locally
make test           # Run tests
make release        # Build production release
make docker-build   # Build Docker image
make docker-run     # Run Docker container
make docker-stop    # Stop Docker container
make docker-push    # Push to Docker Hub
make compose-up     # Start with docker-compose
make compose-down   # Stop docker-compose
make clean          # Clean build artifacts
```

## 🌍 Internationalization (i18n)

MalachiMQ supports **Brazilian Portuguese (pt_BR)** and **American English (en_US)**.

### Configuration

```elixir
config :malachimq, locale: "pt_BR"
```

### Runtime Change

```elixir
MalachiMQ.I18n.set_locale("en_US")
MalachiMQ.I18n.locale()
```

## 📊 User Management (Elixir)

```elixir
MalachiMQ.Auth.list_users()
MalachiMQ.Auth.add_user("myuser", "mypass", [:produce, :consume])
MalachiMQ.Auth.remove_user("myuser")
MalachiMQ.Auth.change_password("myuser", "newpass")
```

## 🏗️ Architecture

- **ETS Tables**: In-memory storage for maximum performance
- **GenServer**: OTP processes for reliability
- **TCP Server**: Custom protocol for low latency
- **Partitioning**: Automatic load distribution across CPU cores

## 📄 License

MIT License

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request