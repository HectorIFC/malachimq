# MalachiMQ

High-performance message queue system built with Elixir/OTP.

[![CI](https://github.com/HectorIFC/malachimq/actions/workflows/ci.yml/badge.svg)](https://github.com/HectorIFC/malachimq/actions/workflows/ci.yml)
[![Release](https://github.com/HectorIFC/malachimq/actions/workflows/release.yml/badge.svg)](https://github.com/HectorIFC/malachimq/actions/workflows/release.yml)
[![Docker Image](https://img.shields.io/docker/v/hectorcardoso/malachimq?label=Docker%20Hub)](https://hub.docker.com/r/hectorcardoso/malachimq)

## 🚀 Quick Start with Docker

### Pull and Run

```bash
docker pull hectorcardoso/malachimq:latest

docker run -d \
  --name malachimq \
  -p 4040:4040 \
  -p 4041:4041 \
  -e MALACHIMQ_ADMIN_PASS=your_secure_password \
  hectorcardoso/malachimq:latest
```

### Using Docker Compose

```bash
git clone https://github.com/HectorIFC/malachimq.git
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
| `MALACHIMQ_ENABLE_TLS` | false | Enable TLS encryption |
| `MALACHIMQ_TLS_CERTFILE` | - | TLS certificate file path |
| `MALACHIMQ_TLS_KEYFILE` | - | TLS private key file path |
| `MALACHIMQ_TLS_CACERTFILE` | - | TLS CA certificate (optional) |

### Custom Users

```bash
docker run -d \
  -e MALACHIMQ_DEFAULT_USERS="user1:pass1:produce,consume;user2:pass2:admin" \
  hectorcardoso/malachimq:latest
```

Format: `username:password:permission1,permission2;...`

Permissions: `admin`, `produce`, `consume`

## 🔒 TLS/SSL Encryption

**⚠️ IMPORTANT**: For production deployments, always enable TLS to encrypt credentials and messages.

### Quick Start with TLS

#### 1. Generate Development Certificates

```bash
./scripts/generate-dev-certs.sh
```

#### 2. Run with TLS Enabled

```bash
docker run -d \
  -p 4040:4040 \
  -v $(pwd)/priv/cert:/certs \
  -e MALACHIMQ_ENABLE_TLS=true \
  -e MALACHIMQ_TLS_CERTFILE=/certs/server.crt \
  -e MALACHIMQ_TLS_KEYFILE=/certs/server.key \
  hectorcardoso/malachimq:latest
```

#### 3. Connect with TLS Client (Node.js)

```javascript
const tls = require('tls');

const client = tls.connect({
  host: 'localhost',
  port: 4040,
  rejectUnauthorized: false  // For self-signed certs (dev only)
}, () => {
  console.log('TLS connected');
  client.write(JSON.stringify({
    action: 'auth',
    username: 'producer',
    password: 'producer123'
  }) + '\n');
});
```

### Production TLS Setup

For production, use certificates from:
- **Let's Encrypt** (free, automated)
- **DigiCert**, **GlobalSign** (commercial CAs)
- **Internal PKI** (corporate environments)

See [TLS Security Advisory](docs/SECURITY_ADVISORY_TLS.md) for complete documentation.

### TLS Features

- ✅ TLS 1.2 and 1.3 support
- ✅ Strong cipher suites (ECDHE, AES-GCM)
- ✅ Perfect Forward Secrecy
- ✅ Mutual TLS (mTLS) support
- ✅ Backward compatible (TLS is optional)

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

### Code Quality Checks

```bash
# Format code
mix format

# Check formatting
mix format --check-formatted

# Run static analysis
mix credo --strict

# Check for security issues
mix deps.audit

# Check for unused dependencies
mix deps.unlock --check-unused
```

### CI/CD

The project uses GitHub Actions for continuous integration:

- ✅ **Automated Tests** - Run on every commit
- ✅ **Multiple Elixir/OTP Versions** - Tested on 3 versions
- ✅ **Code Quality** - Credo, formatting, security checks
- ✅ **Docker Build** - Verified on every PR
- ✅ **Automatic Releases** - On merge to main

See [CI/CD Documentation](docs/CI_CD.md) for details.
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

We welcome contributions! Please follow these guidelines:

### Before You Start

1. Check existing issues and PRs
2. Discuss major changes in an issue first
3. Read [CI/CD Documentation](docs/CI_CD.md)

### Development Process

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feat/amazing-feature`)
3. **Make** your changes with tests
4. **Run** quality checks:
   ```bash
   mix format
   mix test
   mix credo --strict
   ```
5. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/):
   ```bash
   git commit -m "feat: add amazing feature"
   ```
6. **Push** to your fork (`git push origin feat/amazing-feature`)
7. **Open** a Pull Request

### PR Requirements

- ✅ **Tests** - All new features must include tests
- ✅ **Documentation** - Update relevant docs
- ✅ **CI Passing** - All checks must pass
- ✅ **Conventional Commits** - Follow commit format
- ✅ **Code Review** - Address review feedback

### Commit Message Format

```
<type>: <description>

Examples:
- feat: add TLS support
- fix: resolve authentication bug
- docs: update README
- test: add unit tests for Auth module
- chore: update dependencies
```

**Types:**
- `feat:` - New feature (→ minor version)
- `fix:` - Bug fix (→ patch version)
- `docs:` - Documentation
- `test:` - Tests
- `refactor:` - Code refactoring
- `chore:` - Maintenance

**Breaking Changes:**
- Add `[major]` to title or `BREAKING CHANGE:` in body

## 🔖 Versioning

This project uses [SEMVER](https://semver.org/) with automated releases.

- **Patch**: Bug fixes → Add `patch` label or default
- **Minor**: New features → Add `minor` label or use `feat:` prefix
- **Major**: Breaking changes → Add `major` label or use `[major]` in title

See [VERSIONING.md](docs/VERSIONING.md) for details.