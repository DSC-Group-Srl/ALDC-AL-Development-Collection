#!/usr/bin/env bash
# Self-test for the test-lane tool (lock, launch.json parsing, publish classification).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && exec "$c" lane.py --self-test; done
echo "no python interpreter on PATH" >&2; exit 2
