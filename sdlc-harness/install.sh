#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
CLAUDE_SDD_LIB_DIR="$HOME/.claude/sdd"
CODEX_SKILLS_DIR="$HOME/.codex/skills"
CODEX_AGENTS_DIR="$HOME/.codex/agents"
CODEX_SDD_LIB_DIR="$HOME/.codex/sdd"

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

mkdir -p "$CLAUDE_SKILLS_DIR" "$CLAUDE_AGENTS_DIR" "$CLAUDE_SDD_LIB_DIR" "$CODEX_SKILLS_DIR" "$CODEX_AGENTS_DIR" "$CODEX_SDD_LIB_DIR"

# Skills. The orchestrator is shared across hosts.
for skill_file in "$SCRIPT_DIR/config/skills/"*.md; do
    [ -f "$skill_file" ] || continue
    skill_name="$(basename "$skill_file" .md)"

    case "$skill_name" in
        sdd)
            mkdir -p "$CLAUDE_SKILLS_DIR/$skill_name" "$CODEX_SKILLS_DIR/$skill_name"
            cp "$skill_file" "$CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
            cp "$skill_file" "$CODEX_SKILLS_DIR/$skill_name/SKILL.md"
            echo "  claude skill: $skill_name"
            echo "  codex skill : $skill_name"
            ;;
        *)
            mkdir -p "$CLAUDE_SKILLS_DIR/$skill_name"
            cp "$skill_file" "$CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
            echo "  claude skill: $skill_name"
            ;;
    esac
done

# Cross-model wrapper + findings schema. The skill invokes the wrapper from here.
for lib_file in "$SCRIPT_DIR/config/lib/"*; do
    [ -f "$lib_file" ] || continue
    cp "$lib_file" "$CLAUDE_SDD_LIB_DIR/"
    cp "$lib_file" "$CODEX_SDD_LIB_DIR/"
    echo "  lib: $(basename "$lib_file")"
done
chmod +x "$CLAUDE_SDD_LIB_DIR/sdd-codex.sh"
chmod +x "$CODEX_SDD_LIB_DIR/sdd-codex.sh"

# Critic agents — host-local subagents the orchestrator uses to review GPT's plans and code.
agent_description() {
    case "$1" in
        plan-critic)  printf '%s' "Reviews GPT-authored test and implementation plans for scope, coverage, economy, and decision-completeness." ;;
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

    {
        printf 'name = "%s"\n' "$agent_name"
        printf 'description = "%s"\n' "$description"
        printf 'model_reasoning_effort = "high"\n'
        printf 'sandbox_mode = "read-only"\n'
        printf "%s\n" "developer_instructions = '''"
        cat "$agent_file"
        printf "\n%s\n" "'''"
    } > "$CODEX_AGENTS_DIR/$agent_name.toml"

    echo "  claude agent: $agent_name"
    echo "  codex agent : $agent_name"
done

echo ""
echo "Installed to:"
printf "  Claude skills : %s\n" "$CLAUDE_SKILLS_DIR"
printf "  Claude agents : %s\n" "$CLAUDE_AGENTS_DIR"
printf "  Codex skills  : %s\n" "$CODEX_SKILLS_DIR"
printf "  Codex agents  : %s\n" "$CODEX_AGENTS_DIR"
printf "  Claude SDD lib: %s\n" "$CLAUDE_SDD_LIB_DIR"
printf "  Codex SDD lib : %s\n" "$CODEX_SDD_LIB_DIR"
echo ""
echo "Requires the codex CLI on PATH and logged in (codex login status)."
echo "Next: run /sdd in Claude, Codex, or Cursor for the full flow."
echo "=========================================="
