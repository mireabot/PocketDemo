#!/bin/bash
# One-time setup: installs the tools in Mintfile and generates the Xcode project.
set -e

for tool in mint ruby; do
  if ! command -v "$tool" >/dev/null; then
    echo "❌ $tool is required. Install it with: brew install $tool"
    exit 1
  fi
done

if ! command -v bun >/dev/null; then
  echo "⚠️  bun is not installed; the backend needs it: brew install oven-sh/bun/bun"
fi

echo "Installing Mint tools (xcodegen, swiftformat, swiftlint)..."
mint bootstrap

echo "Generating Package.swift files..."
ruby ./scripts/dev/packagebot/packagebot.rb

echo "Generating PocketDemo.xcodeproj..."
mint run xcodegen generate --spec project.yml

if command -v bun >/dev/null; then
  echo "Installing backend dependencies..."
  (cd backend && bun install)
fi

echo "✨ Bootstrap complete. Run 'make backend' and 'make open'."
