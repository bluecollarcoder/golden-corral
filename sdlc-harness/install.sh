#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
CLAUDE_SDD_LIB_DIR="$HOME/.claude/sdd"

die() {
    echo "ERROR: $1" >&2
    exit 1
}

echo "=========================================="
echo "Installing SDD Harness"
echo "=========================================="

[ -d "$SCRIPT_DIR/config/skills" ] || die "config/skills/ not found — run install.sh from the repository root"
[ -d "$SCRIPT_DIR/config/agents" ] || die "config/agents/ not found — run install.sh from the repository root"
[ -d "$SCRIPT_DIR/config/lib" ] || die "config/lib/ not found — run install.sh from the repository root"

mkdir -p "$CLAUDE_SKILLS_DIR" "$CLAUDE_AGENTS_DIR" "$CLAUDE_SDD_LIB_DIR"

# Orchestrator skill — Claude only. It drives the workflow and reaches GPT through the
# codex wrapper, so no Codex-side skill install is needed.
for skill_file in "$SCRIPT_DIR/config/skills/"*.md; do
    [ -f "$skill_file" ] || continue
    skill_name="$(basename "$skill_file" .md)"
    mkdir -p "$CLAUDE_SKILLS_DIR/$skill_name"
    cp "$skill_file" "$CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
    echo "  skill: $skill_name"
done

# Cross-model wrapper + findings schema. The skill invokes the wrapper from here.
for lib_file in "$SCRIPT_DIR/config/lib/"*; do
    [ -f "$lib_file" ] || continue
    cp "$lib_file" "$CLAUDE_SDD_LIB_DIR/"
    echo "  lib: $(basename "$lib_file")"
done
chmod +x "$CLAUDE_SDD_LIB_DIR/sdd-codex.sh"

# Critic agents — Claude subagents the orchestrator uses to review GPT's code.
agent_description() {
    case "$1" in
        test-critic)  printf '%s' "Reviews tests for coverage, failure quality, mock fidelity, and missing assertions." ;;
        code-critic)  printf '%s' "Reviews implementation for correctness, security, performance, maintainability, and verification gaps." ;;
        *)            printf '%s' "Evidence-based SDD critic agent." ;;
    esac
}

for agent_file in "$SCRIPT_DIR/config/agents/"*.md; do
    [ -f "$agent_file" ] || continue
    agent_name="$(basename "$agent_file" .md)"
    description="$(agent_description "$agent_name")"

    {
        printf -- '---\n'
        printf 'name: %s\n' "$agent_name"
        printf 'description: %s\n' "$description"
        printf 'tools: Read, Grep, Glob, Bash\n'
        printf -- '---\n\n'
        cat "$agent_file"
    } > "$CLAUDE_AGENTS_DIR/$agent_name.md"

    echo "  agent: $agent_name"
done

echo ""
echo "Installed to:"
printf "  Claude skills : %s\n" "$CLAUDE_SKILLS_DIR"
printf "  Claude agents : %s\n" "$CLAUDE_AGENTS_DIR"
printf "  SDD lib       : %s\n" "$CLAUDE_SDD_LIB_DIR"
echo ""
echo "Requires the codex CLI on PATH and logged in (codex login status)."
echo "Next: run /sdd in your workspace to scaffold .sdd/TASK and start the Spec phase."
echo "=========================================="
