#!/bin/bash
set -e

# Script to bump version in mix.exs
# Usage: ./scripts/bump-version.sh [major|minor|patch]

BUMP_TYPE=${1:-patch}

# Get current version from mix.exs
CURRENT_VERSION=$(grep '@version' mix.exs | head -1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')

echo "Current version: $CURRENT_VERSION"

# Parse version
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]}
PATCH=${VERSION_PARTS[2]}

# Bump version based on type
case $BUMP_TYPE in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Invalid bump type: $BUMP_TYPE"
    echo "Usage: $0 [major|minor|patch]"
    exit 1
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "New version: $NEW_VERSION"

# Update version in mix.exs
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s/@version \".*\"/@version \"$NEW_VERSION\"/" mix.exs
else
  # Linux
  sed -i "s/@version \".*\"/@version \"$NEW_VERSION\"/" mix.exs
fi

echo "Version updated in mix.exs"
echo "NEW_VERSION=$NEW_VERSION" >> $GITHUB_OUTPUT 2>/dev/null || echo "NEW_VERSION=$NEW_VERSION"
