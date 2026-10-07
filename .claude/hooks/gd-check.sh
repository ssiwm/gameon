#!/usr/bin/env bash
# Hook PostToolUse (Edit|Write): po zmianie pliku .gd odpala projekt headless i ostrzega o błędach
# parsowania/kompilacji. Tylko ostrzega — zawsze kończy się kodem 0 i nigdy nie blokuje.
f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$f" in *.gd) ;; *) exit 0 ;; esac
command -v godot >/dev/null || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}/prototype" 2>/dev/null || exit 0
out=$(timeout 20 godot --headless --path . --quit-after 2 2>&1 \
  | grep -a -E "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script" | head -8)
[ -z "$out" ] && exit 0
jq -n --arg m "Godot: błędy skryptów po edycji $(basename "$f"):
$out" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
