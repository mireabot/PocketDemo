#!/bin/bash
set -euo pipefail
repo_path="$(cd "$(dirname "$0")/.." && pwd)"
run_dir="$(mktemp -d /private/tmp/pocket-ios-verify.XXXXXX)"
package_dir="${POCKET_VERIFY_PACKAGE_DIR:-/private/tmp/pocket-ios-verification}"
backend_pid=""
cleanup() {
  if [ -n "$backend_pid" ]; then kill "$backend_pid" 2>/dev/null || true; wait "$backend_pid" 2>/dev/null || true; fi
  rm -rf "$run_dir"
}
trap cleanup EXIT
mkdir -p "$package_dir/Sources/VerifySync"
cp "$repo_path/scripts/verification/"*.swift "$package_dir/Sources/VerifySync/"
cp "$repo_path/Layers/Features/PocketRecordings/Sources/Repository/RecordingsRepository.swift" "$package_dir/Sources/VerifySync/"
python3 - "$repo_path" "$package_dir" <<'PY'
from pathlib import Path
import json,sys
repo,package=map(Path,sys.argv[1:])
(package/'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "PocketIOSVerification", platforms: [.macOS(.v26)], dependencies: [
    .package(path: '''+json.dumps(str(repo/'Layers/Services/PocketSync'))+'''),
    .package(path: '''+json.dumps(str(repo/'Layers/Foundation/Domain'))+'''),
    .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.9.4"),
    .package(path: '''+json.dumps(str(repo/'Layers/Foundation/PocketNetworking'))+'''),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.6.1")
], targets: [.executableTarget(name: "VerifySync", dependencies: ["PocketSync", "PocketNetworking", "Domain", .product(name: "Dependencies", package: "swift-dependencies"), .product(name: "GRDB", package: "GRDB.swift")])])
''')
PY
port="${POCKET_VERIFY_PORT:-18787}"
PORT="$port" DATA_DIR="$run_dir/backend" bun "$repo_path/scripts/verification/RecoveryBackend.ts" > "$run_dir/backend.log" 2>&1 &
backend_pid=$!
for attempt in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$backend_pid" 2>/dev/null; then cat "$run_dir/backend.log"; exit 1; fi
  sleep 0.1
done
POCKET_VERIFY_URL="http://127.0.0.1:$port" swift run --package-path "$package_dir" VerifySync
