#!/bin/sh
# sdd-codex.sh — thin wrapper around `codex exec` for the SDD orchestrator.
#
# The orchestrator (Claude) calls this to reach the second model (GPT) without a
# human relaying messages. It centralizes every codex flag so the skill prompt
# does not have to.
#
# Modes:
#   plan-review <prompt-file> <out-json>   GPT critiques a plan, read-only,
#                                          emits JSON matching findings.schema.json
#   build       <prompt-file> [out-msg]    GPT authors test/logic code, workspace-write
#   fix         <prompt-file> [out-msg]    GPT applies blocking findings, workspace-write
#
# The prompt is read from <prompt-file> via stdin. The repo root is the current
# git toplevel (falls back to the working directory). Model defaults to gpt-5.5,
# overridable with SDD_CODEX_MODEL.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$SCRIPT_DIR/findings.schema.json"
MODEL="${SDD_CODEX_MODEL:-gpt-5.5}"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

die() { echo "sdd-codex: $1" >&2; exit 2; }

[ "$#" -ge 1 ] || die "usage: sdd-codex.sh {plan-review|build|fix} <prompt-file> [out]"
MODE="$1"; shift

case "$MODE" in
  plan-review)
    [ "$#" -eq 2 ] || die "usage: sdd-codex.sh plan-review <prompt-file> <out-json>"
    PROMPT_FILE="$1"; OUT="$2"
    [ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"
    [ -f "$SCHEMA" ] || die "schema not found: $SCHEMA"
    codex exec \
      --sandbox read-only \
      --skip-git-repo-check \
      --color never \
      -C "$REPO" \
      -m "$MODEL" \
      --output-schema "$SCHEMA" \
      -o "$OUT" \
      - < "$PROMPT_FILE"
    ;;
  build|fix)
    [ "$#" -ge 1 ] || die "usage: sdd-codex.sh $MODE <prompt-file> [out-msg]"
    PROMPT_FILE="$1"; OUT="${2:-}"
    [ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"
    if [ -n "$OUT" ]; then
      codex exec \
        --sandbox workspace-write \
        --skip-git-repo-check \
        --color never \
        -C "$REPO" \
        -m "$MODEL" \
        -o "$OUT" \
        - < "$PROMPT_FILE"
    else
      codex exec \
        --sandbox workspace-write \
        --skip-git-repo-check \
        --color never \
        -C "$REPO" \
        -m "$MODEL" \
        - < "$PROMPT_FILE"
    fi
    ;;
  *)
    die "unknown mode: $MODE (expected plan-review, build, or fix)"
    ;;
esac
