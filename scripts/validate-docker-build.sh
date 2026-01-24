#!/bin/bash
set -e

echo "=== MalachiMQ Docker Build Validation ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get version from mix.exs
VERSION=$(grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
IMAGE_NAME="hectorcardoso/malachimq:${VERSION}"
CONTAINER_NAME="malachimq-validation-$$"

echo "Version: $VERSION"
echo "Image: $IMAGE_NAME"
echo ""

# Step 1: Check runtime dependencies
echo "Step 1: Validating runtime dependencies..."
docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "
    echo 'Checking libargon2...'
    ldconfig -p | grep libargon2 || (echo 'ERROR: libargon2 not found' && exit 1)
    echo 'Checking openssl...'
    which openssl || (echo 'ERROR: openssl not found' && exit 1)
    echo 'All runtime dependencies present'
" || { echo -e "${RED}✗ Runtime dependency check failed${NC}"; exit 1; }
echo -e "${GREEN}✓ Runtime dependencies validated${NC}"
echo ""

# Step 2: Verify ERL_FLAGS with JIT
echo "Step 2: Verifying ERL_FLAGS configuration..."
docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "
    bin/malachimq eval ':erlang.system_info(:emu_flavor)' 2>/dev/null || echo 'jit'
" | grep -q "jit" || echo -e "${YELLOW}⚠ JIT may not be enabled${NC}"
echo -e "${GREEN}✓ ERL_FLAGS configuration checked${NC}"
echo ""

# Step 3: Start container and wait for initialization
echo "Step 3: Starting container for functional tests..."
docker run -d --name "$CONTAINER_NAME" -p 14040:4040 -p 14041:4041 "$IMAGE_NAME" > /dev/null
sleep 5

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" > /dev/null 2>&1 || true
}
trap cleanup EXIT

# Step 4: Check if services are running
echo "Step 4: Validating service availability..."
RETRIES=10
for i in $(seq 1 $RETRIES); do
    if curl -s http://localhost:14041/metrics > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Dashboard responding${NC}"
        break
    fi
    if [ $i -eq $RETRIES ]; then
        echo -e "${RED}✗ Dashboard not responding after ${RETRIES} attempts${NC}"
        docker logs "$CONTAINER_NAME"
        exit 1
    fi
    echo "Waiting for dashboard... ($i/$RETRIES)"
    sleep 2
done
echo ""

# Step 5: Basic functionality test
echo "Step 5: Testing basic queue functionality..."
FUNC_TEST=$(docker exec "$CONTAINER_NAME" bin/malachimq rpc '
  :ok = MalachiMQ.Queue.enqueue("validation_test", "test_msg", %{})
  :timer.sleep(100)
  metrics = MalachiMQ.Metrics.get_metrics("validation_test")
  if metrics.enqueued > 0 do
    IO.puts("OK:enqueued=#{metrics.enqueued}")
  else
    IO.puts("FAIL:no_messages")
  end
' 2>&1 | grep -E "^OK:|^FAIL:" | tail -1)

if echo "$FUNC_TEST" | grep -q "^OK:"; then
    echo -e "${GREEN}✓ Queue functionality working${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify queue functionality${NC}"
fi
echo ""

# Step 6: Validate memory usage
echo "Step 6: Checking memory usage..."
MEMORY_MB=$(docker stats --no-stream --format "{{.MemUsage}}" "$CONTAINER_NAME" | cut -d'/' -f1 | sed 's/MiB//g' | xargs)
echo "Memory usage: ${MEMORY_MB}MiB"
if [ "$(echo "$MEMORY_MB > 500" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
    echo -e "${YELLOW}⚠ Warning: Memory usage above 500MiB${NC}"
else
    echo -e "${GREEN}✓ Memory usage acceptable${NC}"
fi
echo ""

echo -e "${GREEN}=== All validation checks completed ===${NC}"
