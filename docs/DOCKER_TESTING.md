# Docker Build Testing Guide

This document describes the comprehensive testing and validation process for MalachiMQ Docker builds.

## Overview

The Docker build process includes three levels of validation:

1. **Build Validation** - Verifies runtime dependencies, configuration, and basic performance
2. **Regression Testing** - Comprehensive functional and performance tests
3. **Full Test Suite** - Complete end-to-end testing workflow

## Prerequisites

- Docker installed and running
- `make` utility
- `curl` and `nc` (netcat) for testing
- `bc` for calculations (optional)

## Quick Start

### Run All Tests

```bash
# Build the image and run all validation tests
make docker-test-all
```

This single command:
1. Builds the Docker image
2. Runs build validation checks
3. Executes regression test suite
4. Reports comprehensive results

## Individual Test Commands

### 1. Build Validation

```bash
make docker-validate
```

**What it tests:**
- ✅ Runtime dependencies present (`libargon2-1`, `openssl`, `libstdc++6`)
- ✅ ERL_FLAGS configuration (JIT enabled)
- ✅ Service availability (TCP port 4040, Dashboard port 4041)
- ✅ Performance benchmark (1000 consumers, 10K messages)
- ✅ Memory usage validation (< 500MiB threshold)

**Expected output:**
```
Step 1: Validating runtime dependencies...
✓ Runtime dependencies validated

Step 2: Verifying ERL_FLAGS configuration...
✓ ERL_FLAGS configuration checked

Step 3: Starting container for functional tests...
Step 4: Validating service availability...
✓ Dashboard responding

Step 5: Running performance benchmark...
Benchmark Results:
  Time: 2453ms
  Messages Processed: 10000
  Messages Acked: 10000
  Throughput: ~4078 msg/s
✓ Performance benchmark passed

Step 6: Checking memory usage...
Memory usage: 145.2MiB
✓ Memory usage acceptable

=== All validation checks completed ===
```

### 2. Regression Testing

```bash
make docker-regression-test
```

**What it tests:**
- Dashboard HTTP endpoint (GET /)
- Metrics endpoint JSON format (GET /metrics)
- SSE stream endpoint (GET /stream)
- TCP server listening on port 4040
- Container process health
- Queue publish/consume workflow
- High-volume throughput (10K messages)
- Memory stability under load (50K messages)
- Concurrent multi-queue operations (10 queues)
- JIT compilation status

**Expected output:**
```
Testing: Dashboard HTTP endpoint... PASS
Testing: Metrics endpoint returns JSON... PASS
Testing: SSE stream endpoint available... PASS
Testing: TCP port listening... PASS
Testing: Container process health... PASS
Testing: Queue publish/consume workflow... PASS
Testing: High-volume message throughput... PASS
Testing: Memory stability under load... PASS (142.5MiB → 156.3MiB)
Testing: Concurrent multi-queue operations... PASS
Testing: JIT compilation enabled... PASS

===================================
Regression Test Summary
===================================
Passed: 10
Failed: 0
===================================
All regression tests passed!
```

## Manual Validation Steps

### Step 1: Build the Image

```bash
make docker-build
```

### Step 2: Verify Runtime Dependencies

```bash
docker run --rm --entrypoint /bin/bash hectorcardoso/malachimq:latest -c "ldconfig -p | grep libargon2"
```

Expected: Output shows `libargon2.so.1`

### Step 3: Test JIT Configuration

```bash
docker run --rm hectorcardoso/malachimq:latest bin/malachimq eval ':erlang.system_info(:emu_flavor)'
```

Expected: `jit`

### Step 4: Run Container and Check Logs

```bash
docker run -d --name test-malachimq -p 4040:4040 -p 4041:4041 hectorcardoso/malachimq:latest
docker logs -f test-malachimq
```

Expected logs:
```
[info] 🚀 Iniciando MalachiMQ...
[info] ✓ Gerenciador de partições iniciado com 800 partições
[info] ✓ Pool de aceitadores TCP iniciado com 8 workers
[info] ✓ Dashboard HTTP iniciado na porta 4041
```

### Step 5: Test Dashboard

```bash
curl http://localhost:4041/
curl http://localhost:4041/metrics
```

### Step 6: Test TCP Protocol

```bash
# Using netcat to test authentication
echo '{"action":"auth","username":"producer","password":"producer123"}' | nc localhost 4040
```

Expected response:
```json
{"s":"ok","token":"<session_token>"}
```

## Performance Benchmarks

### Baseline Performance Metrics

On a typical 8-core system:

| Metric | Expected Value |
|--------|---------------|
| Consumer creation rate | > 1000/sec |
| Message throughput | > 3000 msg/sec |
| Memory per consumer | < 5 KB |
| Container memory (idle) | < 150 MiB |
| Container memory (under load) | < 300 MiB |

### Custom Benchmark

```bash
docker exec malachimq bin/malachimq eval '
  MalachiMQ.Benchmark.spawn_consumers("bench", 10000)
  MalachiMQ.Benchmark.send_messages("bench", 100000)
  :timer.sleep(5000)
  metrics = MalachiMQ.Metrics.get_metrics("bench")
  IO.inspect(metrics)
'
```

## Troubleshooting

### Validation Script Fails on Step 1 (Dependencies)

**Problem:** `libargon2` not found

**Solution:** Rebuild the image - the Dockerfile was updated to include `libargon2-1`:
```bash
docker rmi hectorcardoso/malachimq:latest
make docker-build
```

### Regression Test Timeout

**Problem:** Dashboard not responding after 10 attempts

**Solution:** Check container logs:
```bash
docker logs <container_name>
```

Common causes:
- Port conflict (another service using 4040/4041)
- Insufficient memory
- Docker daemon issues

### Low Throughput Performance

**Problem:** Throughput < 1000 msg/s

**Possible causes:**
1. System under heavy load
2. JIT not enabled (check platform support)
3. Limited CPU cores

**Diagnosis:**
```bash
docker exec <container_name> bin/malachimq eval 'MalachiMQ.Benchmark.system_info()'
```

### Memory Usage Exceeds Threshold

**Problem:** Container using > 500MiB during validation

**Solutions:**
- Reduce partition multiplier: `-e MALACHIMQ_PARTITION_MULTIPLIER=50`
- Check for memory leaks in application code
- Verify garbage collection is working

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Docker Build & Test

on: [push, pull_request]

jobs:
  docker-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Docker image
        run: make docker-build
      
      - name: Run validation tests
        run: make docker-validate
      
      - name: Run regression tests
        run: make docker-regression-test
      
      - name: Cleanup
        if: always()
        run: docker system prune -f
```

### GitLab CI Example

```yaml
docker-test:
  stage: test
  image: docker:latest
  services:
    - docker:dind
  script:
    - make docker-build
    - make docker-test-all
  artifacts:
    when: on_failure
    paths:
      - docker-logs/
```

## Best Practices

1. **Always run full test suite before pushing images:**
   ```bash
   make docker-test-all
   ```

2. **Test on target platforms if building multi-arch:**
   ```bash
   docker buildx build --platform linux/amd64,linux/arm64 .
   ```

3. **Validate local changes before Docker build:**
   ```bash
   mix test && make docker-build
   ```

4. **Monitor resource usage during tests:**
   ```bash
   docker stats
   ```

5. **Clean up test containers regularly:**
   ```bash
   docker container prune -f
   ```

## Automated Testing Workflow

Recommended workflow for development:

```bash
# 1. Make code changes
vim lib/malachimq/queue.ex

# 2. Test locally
mix test

# 3. Build Docker image
make docker-build

# 4. Run validation
make docker-validate

# 5. Run regression tests
make docker-regression-test

# 6. If all pass, tag and push
docker push hectorcardoso/malachimq:latest
```

## Script Locations

- **Validation Script:** `scripts/validate-docker-build.sh`
- **Regression Test:** `scripts/docker-regression-test.sh`
- **Makefile Targets:** `Makefile`

## Support

For issues or questions:
- GitHub Issues: https://github.com/HectorIFC/malachimq/issues
- Documentation: https://hectorifc.github.io/malachimq
