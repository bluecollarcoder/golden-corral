#!/bin/sh
# sdd-codex.sh — thin wrapper around `codex exec` for delegated SDD authoring.
#
# Usage:
#   sdd-codex.sh <prompt-file> [out-msg]
#
# The prompt is read from <prompt-file> via stdin. The repo root is the current
# git toplevel (falls back to the working directory). Set SDD_CODEX_MODEL to
# override the Codex default model. The delegated process can edit the workspace,
# but all host-owned .sdd state is hidden by an ephemeral permission profile.

set -eu

MODEL="${SDD_CODEX_MODEL:-}"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

die() { echo "sdd-codex: $1" >&2; exit 2; }

codex_exec() {
  if [ -n "$MODEL" ]; then
    codex exec -m "$MODEL" "$@"
  else
    codex exec "$@"
  fi
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "usage: sdd-codex.sh <prompt-file> [out-msg]"
PROMPT_FILE="$1"
OUT="${2:-}"

[ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"

run_delegate() {
  codex_exec \
    --strict-config \
    --ephemeral \
    --skip-git-repo-check \
    --color never \
    -C "$REPO" \
    -c 'default_permissions="sdd-delegate"' \
    -c 'permissions.sdd-delegate={ extends = ":workspace", filesystem = { ":workspace_roots" = { ".sdd" = "deny" } } }' \
    "$@" \
    - < "$PROMPT_FILE"
}

if [ -n "$OUT" ]; then
  run_delegate -o "$OUT"
else
  run_delegate
fi
