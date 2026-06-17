#!/usr/bin/env bash
# Convenience script to use any Chatvolt skill from this repo
# Usage: ./chatvolt.sh <skill> <script> [args...]
# Example: ./chatvolt.sh agent-test test-agent.sh "sk-..." "agent-id"

set -euo pipefail

SKILL="${1:?Usage: $0 <skill> <script> [args...]}"
SCRIPT="${2:?Usage: $0 <skill> <script> [args...]}"
shift 2

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)/${SKILL}"

if [ ! -d "$SKILL_DIR" ]; then
  echo "Available skills:"
  for d in "$(dirname "$0")"/*/; do
    name=$(basename "$d")
    [ "$name" != ".git" ] && echo "  - $name"
  done
  exit 1
fi

SCRIPT_PATH="${SKILL_DIR}/scripts/${SCRIPT}"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Available scripts in ${SKILL}:"
  ls "${SKILL_DIR}/scripts/"
  exit 1
fi

exec "$SCRIPT_PATH" "$@"
