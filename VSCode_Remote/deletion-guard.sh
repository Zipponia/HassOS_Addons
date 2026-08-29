#!/usr/bin/env bash
# Claude Code PreToolUse guard.
#
# The add-on lets Claude run commands without prompting (permissions.allow in
# ~/.claude/settings.json). This hook is what puts the confirmation back for
# commands that DELETE things — files, containers, volumes, packages, add-ons.
#
# Patterns are anchored at command position (start of line, or after ; & | && ||)
# so a harmless "grep rm file" is not flagged.
set -u

cmd=$(jq -r ".tool_input.command // empty" 2>/dev/null)
[ -z "${cmd}" ] && exit 0

POS='(^|[;&|]\s*)(sudo\s+)?'

patterns=(
  "${POS}"'(rm|rmdir|shred|unlink|truncate)(\s|$)'
  "${POS}"'docker\s+(rm|rmi)(\s|$)'
  "${POS}"'docker\s+(volume|network|image|container|system)\s+(rm|prune)'
  "${POS}"'(apt|apt-get|dpkg)\s+(remove|purge|autoremove)'
  "${POS}"'git\s+clean(\s|$)'
  "${POS}"'ha\s+.*(uninstall|remove)(\s|$)'
  "${POS}"'mkfs'
  '(^|\s)--?delete(\s|$)'
  '-X\s*DELETE|--request\s*DELETE'
  '(^|\s)dd\s.*\sof='
  '\smv\s+\S+\s+/dev/null'
)

for p in "${patterns[@]}"; do
  if printf "%s" "${cmd}" | grep -qE -- "${p}"; then
    jq -nc --arg r "Comando di cancellazione rilevato: richiede conferma esplicita." \
      "{hookSpecificOutput:{hookEventName:\"PreToolUse\",permissionDecision:\"ask\",permissionDecisionReason:\$r}}"
    exit 0
  fi
done
exit 0
