#!/bin/bash
# Creates a local Swift package under Layers/<Layer>/<Name> and registers it in the XcodeGen specs.
# Usage: add_local_package.sh [Name] [Features|Services|Foundation]
# With no arguments it asks interactively. Package.swift is generated afterwards by `make layers`.

set -e

package_name="$1"
category="$2"

if [ -z "$package_name" ]; then
  read -p "Enter the package name: " package_name
fi

if [ -z "$category" ]; then
  echo "Choose the layer:"
  echo "1) Features"
  echo "2) Services"
  echo "3) Foundation"
  read -p "Enter the number: " category_number
  case $category_number in
    1) category="Features" ;;
    2) category="Services" ;;
    3) category="Foundation" ;;
    *) echo "Invalid layer."; exit 1 ;;
  esac
fi

case $category in
  Features|Services|Foundation) ;;
  *) echo "❌ Layer must be Features, Services or Foundation (got '$category')."; exit 1 ;;
esac

if ! [[ "$package_name" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "❌ Package name must be UpperCamelCase (got '$package_name')."
  exit 1
fi

mkdir -p temp

FILE_BASE="project-base.yml"
echo "🔧 Updating $FILE_BASE ..."
cp "$FILE_BASE" "temp/$(basename "$FILE_BASE").bak"
if grep -q "^[[:space:]]*$package_name:" "$FILE_BASE"; then
  echo "⚠️  Package '$package_name' already exists in $FILE_BASE. Skipping."
elif grep -q '# External Packages' "$FILE_BASE"; then
  sed -i '' "/# External Packages/i\\
  $package_name:\\
    path: Layers/$category/$package_name\\
    group: Layers/$category\\
" "$FILE_BASE"
  echo "✅ Package entry added to $FILE_BASE."
else
  echo "⚠️  '# External Packages' marker not found in $FILE_BASE. Skipping."
fi

FILE_APP="project.yml"
echo "🔧 Updating $FILE_APP ..."
cp "$FILE_APP" "temp/$(basename "$FILE_APP").bak"
if grep -q "^[[:space:]]*- package: $package_name$" "$FILE_APP"; then
  echo "⚠️  Dependency on '$package_name' already exists in $FILE_APP. Skipping."
elif grep -q '# External SPM Packages' "$FILE_APP"; then
  awk -v dep="      - package: $package_name" '
    { if ($0 ~ /# External SPM Packages/ && !inserted) { print dep; inserted = 1 } print }
  ' "$FILE_APP" > temp/project.yml.tmp && mv temp/project.yml.tmp "$FILE_APP"
  echo "✅ Dependency added to $FILE_APP."
else
  echo "⚠️  '# External SPM Packages' marker not found in $FILE_APP. Skipping."
fi

package_folder="Layers/$category/$package_name"
sources_folder="$package_folder/Sources"
mkdir -p "$sources_folder"
source_file="$sources_folder/$package_name.swift"
if [ ! -f "$source_file" ]; then
  printf 'import Foundation\n\npublic enum %s {}\n' "$package_name" > "$source_file"
  echo "✅ Created $source_file."
fi

echo "🎉 $package_name created in Layers/$category."
