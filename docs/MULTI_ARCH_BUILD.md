# Multi-Architecture Docker Build Guide

This guide explains how to build and push multi-architecture Docker images for MalachiMQ.

## Prerequisites

1. Docker Desktop installed (or Docker Engine + QEMU)
2. Docker Hub account with push permissions
3. Docker Buildx enabled (comes by default with Docker Desktop)

## Initial Setup

### 1. Log in to Docker Hub

```bash
docker login
```

Enter your credentials when prompted.

### 2. Configure multi-architecture builder

```bash
make docker-buildx-setup
```

Or manually:

```bash
docker buildx create --name malachimq-builder --use --bootstrap
docker buildx inspect --bootstrap
```

## Local Build (for testing)

### Build only for your current architecture

```bash
make docker-build
```

### Multi-architecture build (AMD64 + ARM64) without push

```bash
make docker-buildx
```

**Note**: The `--load` flag only works for one architecture at a time. To test both, you need to push to a registry.

## Build and Push to Docker Hub

### Multi-architecture push

```bash
make docker-buildx-push
```

This will:
1. Build for `linux/amd64` and `linux/arm64`
2. Create multi-architecture manifest
3. Push to Docker Hub with tags:
   - `hectorcardoso/malachimq:VERSION` (e.g.: 0.2.0)
   - `hectorcardoso/malachimq:latest`

### Custom push

```bash
# Specify different platforms
PLATFORMS=linux/amd64,linux/arm64,linux/arm/v7 make docker-buildx-push

# Use different username
DOCKER_USERNAME=myuser make docker-buildx-push

# Manually specify version
VERSION=1.0.0 make docker-buildx-push
```

## Verify images on Docker Hub

```bash
# View available platforms
docker buildx imagetools inspect hectorcardoso/malachimq:latest
```

Expected output:
```
Name:      docker.io/hectorcardoso/malachimq:latest
MediaType: application/vnd.docker.distribution.manifest.list.v2+json
Digest:    sha256:...
           
Manifests: 
  Name:      docker.io/hectorcardoso/malachimq:latest@sha256:...
  MediaType: application/vnd.docker.distribution.manifest.v2+json
  Platform:  linux/amd64
             
  Name:      docker.io/hectorcardoso/malachimq:latest@sha256:...
  MediaType: application/vnd.docker.distribution.manifest.v2+json
  Platform:  linux/arm64
```

## Test on different architectures

### macOS with Apple Silicon (ARM64)

```bash
docker pull hectorcardoso/malachimq:latest
docker run --rm hectorcardoso/malachimq:latest uname -m
# Output: aarch64
```

### Linux x86_64 (AMD64)

```bash
docker pull hectorcardoso/malachimq:latest
docker run --rm hectorcardoso/malachimq:latest uname -m
# Output: x86_64
```

### Force a specific architecture

```bash
# Force ARM64 even on AMD64
docker run --platform linux/arm64 hectorcardoso/malachimq:latest

# Force AMD64 even on ARM64 (with QEMU emulation)
docker run --platform linux/amd64 hectorcardoso/malachimq:latest
```

## Automation with GitHub Actions

The workflow in `.github/workflows/docker-build.yml` automates the process:

- **Push to `main`**: Automatic build and push with `latest` tag
- **Tag `v*`**: Build and push with specific version (e.g.: `v0.2.0` → tag `0.2.0`)
- **Pull Request**: Build only (no push)

### Configure secrets on GitHub

1. Go to `Settings` → `Secrets and variables` → `Actions`
2. Add the `DOCKERHUB_TOKEN` secret:
   - Go to [Docker Hub Security](https://hub.docker.com/settings/security)
   - Click "New Access Token"
   - Copy the token and paste into GitHub secret

## Troubleshooting

### Error: "no matching manifest"

This means the image doesn't have a build for your architecture. Solution:
- Push with `make docker-buildx-push`
- Or force emulation: `docker run --platform linux/amd64 ...`

### Builder not found

```bash
docker buildx ls
docker buildx create --name malachimq-builder --use
```

### Layer cache

The workflow uses GitHub Actions cache to speed up builds:
```bash
cache-from: type=gha
cache-to: type=gha,mode=max
```

### Local build very slow

QEMU emulation (for ARM64 on AMD64 or vice versa) is slow. Use:
```bash
# Build only for your architecture
docker build -t hectorcardoso/malachimq:latest .
```

## Useful commands

```bash
# View available builders
docker buildx ls

# Remove builder
docker buildx rm malachimq-builder

# Inspect remote image
docker buildx imagetools inspect hectorcardoso/malachimq:latest

# View disk space used by build cache
docker buildx du

# Clean build cache
docker buildx prune -af
```

## Summary of Make commands

| Command | Description |
|---------|-----------|
| `make docker-build` | Traditional build (current architecture) |
| `make docker-buildx-setup` | Configure multi-architecture builder |
| `make docker-buildx` | Multi-architecture build (no push) |
| `make docker-buildx-push` | Build and push multi-architecture |
| `make docker-run` | Run container locally |
| `make docker-stop` | Stop and remove container |

## References

- [Docker Buildx documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [Multi-platform images](https://docs.docker.com/build/building/multi-platform/)
- [GitHub Actions for Docker](https://github.com/docker/build-push-action)
