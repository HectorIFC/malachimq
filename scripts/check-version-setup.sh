#!/bin/bash
set -e

echo "🔍 Checking Versioning Configuration..."
echo ""

# Check if mix.exs exists
if [ -f "mix.exs" ]; then
    VERSION=$(grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
    echo "✅ mix.exs found"
    echo "   Current version: $VERSION"
else
    echo "❌ mix.exs not found"
    exit 1
fi

# Check if bump script exists and is executable
if [ -f "scripts/bump-version.sh" ]; then
    if [ -x "scripts/bump-version.sh" ]; then
        echo "✅ scripts/bump-version.sh (executable)"
    else
        echo "⚠️  scripts/bump-version.sh (not executable)"
        echo "   Run: chmod +x scripts/bump-version.sh"
    fi
else
    echo "❌ scripts/bump-version.sh not found"
fi

# Check if GitHub workflow exists
if [ -f ".github/workflows/release.yml" ]; then
    echo "✅ .github/workflows/release.yml"
else
    echo "❌ .github/workflows/release.yml not found"
fi

# Check if CHANGELOG exists
if [ -f "CHANGELOG.md" ]; then
    echo "✅ CHANGELOG.md"
else
    echo "⚠️  CHANGELOG.md not found"
fi

# Check Makefile for dynamic version
if grep -q 'VERSION ?= $(shell grep' Makefile 2>/dev/null; then
    echo "✅ Makefile with dynamic version"
else
    echo "⚠️  Makefile doesn't use dynamic version from mix.exs"
fi

echo ""
echo "📋 Summary:"
echo "   Current version: $VERSION"
echo "   Branch: $(git branch --show-current)"
echo "   Last commit: $(git log -1 --pretty=format:'%h - %s')"
echo ""

# Check for GitHub secrets (can't actually check, just remind)
echo "🔐 Reminder: Configure secrets on GitHub:"
echo "   - DOCKER_USERNAME"
echo "   - DOCKER_PASSWORD"
echo ""

echo "✨ Versioning system configured!"
echo "📖 See docs/VERSIONING.md for more details"
