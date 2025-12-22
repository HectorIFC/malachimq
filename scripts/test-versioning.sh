#!/bin/bash
# Versioning system test script
# This script does NOT make real commits, only simulates

set -e

echo "🧪 Testing Versioning System"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get current version
CURRENT_VERSION=$(grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
echo "📦 Current Version: ${BLUE}${CURRENT_VERSION}${NC}"
echo ""

# Test patch bump
echo "1️⃣  Testing: ${YELLOW}Patch Bump${NC}"
echo "   Command: ./scripts/bump-version.sh patch"
# Save current version
cp mix.exs mix.exs.backup
./scripts/bump-version.sh patch > /dev/null 2>&1
NEW_VERSION=$(grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
echo "   Result: ${CURRENT_VERSION} → ${GREEN}${NEW_VERSION}${NC}"
# Restore
mv mix.exs.backup mix.exs
echo ""

# Test minor bump
echo "2️⃣  Testing: ${YELLOW}Minor Bump${NC}"
echo "   Command: ./scripts/bump-version.sh minor"
cp mix.exs mix.exs.backup
./scripts/bump-version.sh minor > /dev/null 2>&1
NEW_VERSION=$(grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
echo "   Result: ${CURRENT_VERSION} → ${GREEN}${NEW_VERSION}${NC}"
mv mix.exs.backup mix.exs
echo ""

# Test major bump
echo "3️⃣  Testing: ${YELLOW}Major Bump${NC}"
echo "   Command: ./scripts/bump-version.sh major"
cp mix.exs mix.exs.backup
./scripts/bump-version.sh major > /dev/null 2>&1
NEW_VERSION=$(grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
echo "   Result: ${CURRENT_VERSION} → ${GREEN}${NEW_VERSION}${NC}"
mv mix.exs.backup mix.exs
echo ""

# Test Makefile version extraction
echo "4️⃣  Testing: ${YELLOW}Makefile Version Extraction${NC}"
MAKE_VERSION=$(make --no-print-directory -f - <<< 'include Makefile
.PHONY: print-version
print-version:
	@echo $(VERSION)' print-version)
echo "   Extracted version: ${GREEN}${MAKE_VERSION}${NC}"
echo ""

# Test workflow file exists
echo "5️⃣  Testing: ${YELLOW}GitHub Workflow${NC}"
if [ -f ".github/workflows/release.yml" ]; then
    echo "   ${GREEN}✓${NC} Workflow exists"
    # Check for required steps
    if grep -q "bump-version.sh" .github/workflows/release.yml; then
        echo "   ${GREEN}✓${NC} Bump script configured"
    fi
    if grep -q "create-release" .github/workflows/release.yml; then
        echo "   ${GREEN}✓${NC} Release creation configured"
    fi
    if grep -q "docker/build-push-action" .github/workflows/release.yml; then
        echo "   ${GREEN}✓${NC} Docker build configured"
    fi
else
    echo "   ${RED}✗${NC} Workflow not found"
fi
echo ""

# Test documentation
echo "6️⃣  Testing: ${YELLOW}Documentation${NC}"
docs=("docs/VERSIONING.md" ".github/QUICKSTART.md" "CHANGELOG.md" ".github/LABELS.md")
for doc in "${docs[@]}"; do
    if [ -f "$doc" ]; then
        echo "   ${GREEN}✓${NC} ${doc}"
    else
        echo "   ${RED}✗${NC} ${doc} (not found)"
    fi
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "${GREEN}✨ Tests Completed!${NC}"
echo ""
echo "Next steps:"
echo "  1. Configure secrets on GitHub"
echo "  2. Create labels with: ./scripts/create-github-labels.sh"
echo "  3. Commit and merge to main"
echo ""
