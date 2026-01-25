#!/bin/bash

# Demo script for MalachiMQ Channel Pub/Sub
# Shows best-effort delivery

set -e

echo "🚀 MalachiMQ Channel Pub/Sub Demo"
echo "=================================="
echo ""
echo "This demo shows:"
echo "  • Best-effort delivery (no message buffering)"
echo "  • Broadcasting to multiple subscribers"
echo "  • Message drop when no subscribers"
echo ""

# Check if MalachiMQ is running
if ! nc -z localhost 4040 2>/dev/null; then
    echo "❌ MalachiMQ is not running on port 4040"
    echo "   Start it with: mix run --no-halt"
    exit 1
fi

echo "✓ MalachiMQ is running"
echo ""

# Test 1: Publish with no subscribers (messages dropped)
echo "Test 1: Publishing with no subscribers (messages will be dropped)"
echo "----------------------------------------------------------------"
node scripts/channel-publisher.js test_demo 5
echo ""
sleep 1

# Test 2: Publish help
echo "Test 2: Show channel-publisher help"
echo "------------------------------------"
node scripts/channel-publisher.js --help | head -20
echo ""

# Test 3: Show channel-subscriber help  
echo "Test 3: Show channel-subscriber help"
echo "-------------------------------------"
node scripts/channel-subscriber.js --help | head -20
echo ""

echo "✅ Demo complete!"
echo ""
echo "To try interactive pub/sub:"
echo "  Terminal 1: node scripts/channel-subscriber.js news"
echo "  Terminal 2: node scripts/channel-publisher.js news 10"
echo ""
echo "For continuous publishing:"
echo "  node scripts/channel-publisher.js news --continuous"
echo ""
