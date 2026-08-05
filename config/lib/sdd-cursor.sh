#!/bin/sh
# sdd-cursor.sh — thin wrapper around Cursor CLI Agent for delegated coding tasks.
#
# Usage:
#   sdd-cursor.sh <prompt-file> [out-msg]
#
# The prompt is opened by this host wrapper and passed via stdin. Cursor runs in
# its default Agent mode at the current git toplevel (falling back to the working
# directory), inside a process-scoped filesystem view where .sdd is empty and
# read-only. Set SDD_CURSOR_MODEL to override Cursor's default model.

set -eu

MODEL="${SDD_CURSOR_MODEL:-}"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SDD_DIR="$REPO/.sdd"
CURSOR_STATE_DIR="${HOME:?}/.cursor"

die() { echo "sdd-cursor: $1" >&2; exit 2; }

cursor_exec() {
  set -- agent \
    --print \
    --output-format text \
    --trust \
    --sandbox enabled \
    --force \
    --workspace "$REPO"
  if [ -n "$MODEL" ]; then
    set -- "$@" --model "$MODEL"
  fi

  if [ -d "$CURSOR_STATE_DIR" ]; then
    bwrap \
      --die-with-parent \
      --new-session \
      --unshare-pid \
      --ro-bind / / \
      --dev-bind /dev /dev \
      --proc /proc \
      --bind /tmp /tmp \
      --bind "$CURSOR_STATE_DIR" "$CURSOR_STATE_DIR" \
      --bind "$REPO" "$REPO" \
      --ro-bind "$EMPTY_SDD" "$SDD_DIR" \
      --chdir "$REPO" \
      "$@"
  else
    bwrap \
      --die-with-parent \
      --new-session \
      --unshare-pid \
      --ro-bind / / \
      --dev-bind /dev /dev \
      --proc /proc \
      --bind /tmp /tmp \
      --bind "$REPO" "$REPO" \
      --ro-bind "$EMPTY_SDD" "$SDD_DIR" \
      --chdir "$REPO" \
      "$@"
  fi
}

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "usage: sdd-cursor.sh <prompt-file> [out-msg]"
PROMPT_FILE="$1"
OUT="${2:-}"

[ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"
[ -d "$SDD_DIR" ] || die "SDD state directory not found: $SDD_DIR"
[ ! -L "$SDD_DIR" ] || die "refusing symlinked SDD state directory: $SDD_DIR"
command -v bwrap >/dev/null 2>&1 || die "bwrap is required for delegated Cursor isolation"

for task_file in "$SDD_DIR"/TASK*.md; do
  [ -e "$task_file" ] || [ -L "$task_file" ] || continue
  [ ! -L "$task_file" ] || die "refusing symlinked TASK file: $task_file"
done

if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$REPO" ls-files -- '.sdd/TASK*.md' | grep -q .; then
    die "TASK files must be untracked so the delegate cannot recover them through Git"
  fi
fi

EMPTY_SDD="$(mktemp -d /tmp/sdd-cursor-empty.XXXXXX)"
trap 'rmdir "$EMPTY_SDD" 2>/dev/null || :' EXIT HUP INT TERM

if [ -n "$OUT" ]; then
  cursor_exec < "$PROMPT_FILE" > "$OUT"
else
  cursor_exec < "$PROMPT_FILE"
fi
