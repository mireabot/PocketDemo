#!/bin/bash
set -e

echo "Formatting Swift files..."
mint run swiftformat .

echo "Linting Swift files..."
mint run swiftlint --quiet
