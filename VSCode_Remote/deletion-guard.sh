#!/usr/bin/env bash
# Claude Code PreToolUse guard.
#
# The add-on lets Claude run commands without prompting (permissions.allow in
# ~/.claude/settings.json). This hook is what puts the confirmation back for
# commands that DELETE or DESTROY things — files, containers, volumes,
# packages, add-ons, uncommitted work, the host itself.
#
# This is a second net, not the only one. It is a set of regular expressions
# over the command text, so it catches the ordinary ways of deleting something
# and cannot catch every way: a script that deletes, a removal assembled from
# variables, or `python -c` are all invisible to it. Backups, git and Claude
# Code's own safety checks are the other nets.
#
# Patterns are anchored at command position so a harmless "grep rm file" is not
# flagged. Command position means: start of a line, after ; & | ( { or a
# backtick, inside $( ), after then/do/else, as the program run by xargs /
# find -exec, or as the string given to `sh -c` / `bash -c` / `eval`.
# Leading whitespace, wrappers (sudo, env, timeout, nohup, nice, …), a
# backslash (\rm) and a path (/bin/rm) are all skipped before the command name.
set -u

cmd=$(jq -r ".tool_input.command // empty" 2>/dev/null)
[ -z "${cmd}" ] && exit 0

# A backslash-newline continues the same command.
cmd=${cmd//$'\\\n'/ }

# Heredoc bodies are data, not commands: a commit message or a file written
# with `cat > f <<EOF` must not prompt because one of its lines starts with
# "rm". The body is kept only when the heredoc feeds something that executes
# it (a shell, ssh, docker, …). If a heredoc never terminates, it was not one:
# scan the whole text.
scan=$(printf '%s\n' "${cmd}" | awk -v q="'" '
  BEGIN {
    open  = "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*"
    strip = "^<<-?[ \t]*[\"" q "]?"
    runs  = "(^|[^A-Za-z0-9_./-])(bash|sh|zsh|dash|ksh|ssh|docker|podman|sudo|su|eval|xargs|source|python3?|perl)([^A-Za-z0-9_]|$)"
  }
  term != "" {
    line = $0
    if (dash) sub(/^\t+/, "", line)
    if (line == term) { term = ""; next }
    if (keep) print
    next
  }
  {
    print
    probe = $0
    gsub(/<<</, "", probe)              # here-strings are not heredocs
    if (match(probe, open)) {
      t = substr(probe, RSTART, RLENGTH)
      dash = (t ~ /^<<-/)
      sub(strip, "", t)
      term = t
      keep = ($0 ~ runs)
    }
  }
  END { if (term != "") exit 3 }
') || scan=${cmd}

# The same text with quoted strings removed, for the one pattern that would
# otherwise fire on a word inside a message.
noquote=$(printf '%s\n' "${scan}" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g")

Q="[\"']"
START='(^|[;&|({`]|\$\(|\b(then|do|else)\s|\bxargs\s+((-\S+|[0-9]+|\S*\{\}\S*)\s+)*|\s-(exec|execdir|ok)\s|\b(ba|da|z|k)?sh\s+(-\S+\s+)*-\S*c\s+'"${Q}"'?|\beval\s+'"${Q}"'?)'
WRAP='((sudo|command|exec|env|nohup|time|nice|ionice|setsid|stdbuf|timeout)\s+((-\S+|\S+=\S*|[0-9.]+[smhd]?)\s+)*)*'
POS="${START}"'\s*'"${WRAP}"'\\?(\S*/)?'
GIT='git\s+(-[cC]\s+\S+\s+|--\S+\s+)*'
RM='(rm|rmdir|shred|unlink|truncate)(\s|$)'

patterns=(
  # --- removal ---------------------------------------------------------------
  "${POS}${RM}"
  "${POS}"'docker\s+(rm|rmi)(\s|$)'
  "${POS}"'docker\s+(volume|network|image|container|system|builder)\s+(rm|prune)'
  "${POS}"'docker[ -]compose\s(.*\s)?(rm|down\s(.*\s)?(-v|--volumes))(\s|$)'
  "${POS}"'(apt|apt-get|dpkg)\s+(-\S+\s+)*(remove|purge|autoremove)'
  "${POS}${GIT}"'clean(\s|$)'
  "${POS}"'mkfs'
  '(^|\s)dd\s.*\sof='
  "${POS}"'mv\s.*\s/dev/null(\s|$)'
  # --- removal run somewhere else --------------------------------------------
  # With the Docker socket mounted, `docker exec <container> rm` is the most
  # likely destructive path on this host. Deliberately loose: any removal verb
  # after `docker exec` or `ssh` asks.
  '\b(docker|podman)\s(.*\s)?exec\s.*[[:space:]"'"'"'/\\]'"${RM}"
  '\bssh\s.*[[:space:]"'"'"'/\\]'"${RM}"
  # --- overwrites that destroy content without deleting ----------------------
  '(^|[;|({]|&&)\s*((:|true)\s*)?>\s*[^>&|[:space:]]'
  "${POS}"'cp\s+(-\S+\s+)*/dev/null\s'
  "${POS}${GIT}"'reset\s(.*\s)?--hard(\s|$)'
  "${POS}${GIT}"'(checkout|restore)\s+(--\s+)?\.(\s|$)'
  # --- Home Assistant / Supervisor -------------------------------------------
  "${POS}"'ha\s(.*\s)?(uninstall|remove|restore|reboot|shutdown|wipe)(\s|$)'
  "${POS}"'docker\s+(stop|kill)\s(.*\s)?(homeassistant|hassio_\S+)(\s|$)'
  '(-X|--request)[[:space:]=]*'"${Q}"'?DELETE'
  '/(addons|apps)/[^/[:space:]]+/uninstall|/host/(reboot|shutdown)|/backups/[^/[:space:]]+/restore'
)

ask() {
  jq -nc --arg r "Comando distruttivo rilevato: richiede conferma esplicita." \
    "{hookSpecificOutput:{hookEventName:\"PreToolUse\",permissionDecision:\"ask\",permissionDecisionReason:\$r}}"
  exit 0
}

for p in "${patterns[@]}"; do
  printf '%s\n' "${scan}" | grep -qE -- "${p}" && ask
done

# --delete / -delete as a real flag (rsync, find, git push), not as a word
# inside a quoted message.
printf '%s\n' "${noquote}" | grep -qE -- '(^|\s)--?delete(-\S+)?(\s|$)' && ask

exit 0
