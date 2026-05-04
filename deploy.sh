#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: ./deploy.sh <version> \"<message>\""
  echo "Example: ./deploy.sh 17 \"Summer term improvements\""
  exit 1
fi

VERSION=$1
MESSAGE=$2
FILE="docs/ClubLens_v${VERSION}.html"

if [ ! -f "$FILE" ]; then
  echo "Error: $FILE not found. Have you saved the new version into docs/?"
  exit 1
fi

git add "$FILE" docs/index.html
git commit -m "v${VERSION}: ${MESSAGE}"
git push

echo ""
echo "✓ v${VERSION} deployed. Live at clublens.vercel.app in ~1 minute."
