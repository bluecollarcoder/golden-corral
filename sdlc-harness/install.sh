#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
CODEX_SKILLS_DIR="$HOME/.agents/skills"
CODEX_AGENTS_DIR="$HOME/.codex/agents"

die() {
    echo "ERROR: $1" >&2
    exit 1
}

echo "=========================================="
echo "Installing SDD Harness"
echo "=========================================="

[ -d "$SCRIPT_DIR/config/skills" ] || die "config/skills/ not found — run install.sh from the repository root"
[ -d "$SCRIPT_DIR/config/agents" ] || die "config/agents/ not found — run install.sh from the repository root"

mkdir -p "$CLAUDE_SKILLS_DIR" "$CLAUDE_AGENTS_DIR"
mkdir -p "$CODEX_SKILLS_DIR" "$CODEX_AGENTS_DIR"

for skill_file in "$SCRIPT_DIR/config/skills/"*.md; do
    [ -f "$skill_file" ] || continue
    skill_name="$(basename "$skill_file" .md)"
    mkdir -p "$CLAUDE_SKILLS_DIR/$skill_name" "$CODEX_SKILLS_DIR/$skill_name"
    cp "$skill_file" "$CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
    cp "$skill_file" "$CODEX_SKILLS_DIR/$skill_name/SKILL.md"
    echo "  skill: $skill_name"
done

agent_description() {
    case "$1" in
        spec-critic)  printf '%s' "Reviews specs for ambiguity, hidden dependencies, scope control, and acceptance criteria gaps." ;;
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
        printf 'sandbox_mode = "read-only"\n'
        printf "developer_instructions = '''\n"
        cat "$agent_file"
        printf "\n'''\n"
    } > "$CODEX_AGENTS_DIR/$agent_name.toml"

    echo "  agent: $agent_name"
done

echo ""
echo "Installed to:"
printf "  Claude skills : %s\n" "$CLAUDE_SKILLS_DIR"
printf "  Claude agents : %s\n" "$CLAUDE_AGENTS_DIR"
printf "  Codex skills  : %s\n" "$CODEX_SKILLS_DIR"
printf "  Codex agents  : %s\n" "$CODEX_AGENTS_DIR"
echo ""
echo "Next: run /sdd-research in your workspace to scaffold TASK.md and start the Spec phase."
echo "=========================================="
