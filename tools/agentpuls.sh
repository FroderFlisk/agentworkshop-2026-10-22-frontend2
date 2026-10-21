#!/usr/bin/env bash
# Agent pulse: tells the board what your agent team looks like and what it is doing right now,
# so that it shows up on /teams. Called by the hooks (.github/hooks/torget.json for GitHub Copilot,
# .claude/settings.json for Claude Code). You never need to run it yourself.
#
#   tools/agentpuls.sh lag        [--harness copilot|claude] [--torr]   send the team's roster now
#   tools/agentpuls.sh aktivitet  [start|done] [--harness ...] [--torr] send one activity line (reads the hook's JSON on stdin)
#   (English aliases: roster = lag, activity = aktivitet, --dry-run = --torr)
#
# --torr prints what would be sent instead of sending it. Try it from your team folder:
#   ../../tools/agentpuls.sh lag --torr
#
# What is sent: the team name, which lab it is built on, the names of the files under the team's .claude/
# (agents, candidates, capabilities with energy, dissolved, timelines, winners, graveyard), the last 20 lines
# of the evolution log, and per tool call: which agent, which tool, and a short target (a file name or the
# first word or two of a command). Never file contents, never whole commands.
#
# Turn it off: create an empty file .agentpuls-off in the repo root, or set AGENTPULS=0.
#
# The rules, because this runs inside the agent's own tool loop:
#   - it always exits 0 and never prints anything (unless --torr), so the hook can never block or confuse
#     the agent;
#   - it does nothing at all if something is missing (no team, no .board-url, no curl);
#   - the network call runs in the background with a 3 second limit, so a slow board never slows the agent.
set -u

TORR=0; HARNESS=""; MODE=""; EVENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --torr|--dry-run) TORR=1;;
    --harness) HARNESS="${2:-}"; shift;;
    lag|roster) MODE=lag;;
    aktivitet|activity) MODE=aktivitet;;
    start|done|stop) EVENT="$1";;
    -h|--help|help) sed -n '2,24p' "$0"; exit 0;;
  esac
  shift
done
[ -n "$MODE" ] || { [ "$TORR" = 1 ] && sed -n '2,24p' "$0"; exit 0; }
[ "${AGENTPULS:-1}" = 0 ] && exit 0

# The repo root is where this script lives: <root>/tools/agentpuls.sh. That holds no matter which
# directory the hook happens to run in.
R=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P) || exit 0
[ -f "$R/.agentpuls-off" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0

URL="${BOARD_URL:-}"
[ -z "$URL" ] && [ -f "$R/.board-url" ] && URL=$(tr -d '[:space:]' < "$R/.board-url")
URL="${URL%/}"
[ -n "$URL" ] || [ "$TORR" = 1 ] || exit 0

# The hook's JSON arrives on stdin. Never wait for it when someone runs this by hand in a terminal.
PAYLOAD=""
if [ ! -t 0 ]; then IFS= read -r -d '' -t 2 PAYLOAD || true; fi

# read -d '' instead of PROG=$(cat <<'PY' ...): bash 3.2 trips over quotes inside a heredoc in $(...).
read -r -d '' PROG <<'PY' || true
import json, os, re, sys

def first(d, *keys):
    for k in keys:
        v = d.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ''

try:
    d = json.loads(sys.stdin.read() or '{}')
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}

event = first(d, 'hook_event_name', 'hookEventName')
tool = first(d, 'toolName', 'tool_name')
# Inside a subagent both Copilot CLI and Claude Code add agentType/agent_type (and agentName on
# subagentStart/subagentStop). That is how we know which agent is working.
agent = first(d, 'agentType', 'agent_type', 'agentName', 'agent_name', 'agentDisplayName')
a = d.get('toolArgs', d.get('tool_input', {}))
if isinstance(a, str):
    try:
        a = json.loads(a)
    except Exception:
        a = {'command': a}
if not isinstance(a, dict):
    a = {}

def short_cmd(cmd):
    # First word (as a file name), plus the second word if it is a plain word or a script name.
    # Never the rest: a command line can hold a token or a password.
    words = cmd.replace('\n', ' ').split()
    while words and (re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', words[0]) or words[0] in ('sudo', 'env', 'time')):
        words.pop(0)
    if not words:
        return ''
    out = [os.path.basename(words[0]) or words[0]]
    if len(words) > 1 and re.fullmatch(r'[A-Za-z][A-Za-z0-9._:/-]{0,40}', words[1]) and len(words[1]) < 41:
        out.append(os.path.basename(words[1].rstrip('/')) or words[1])
    return ' '.join(out)

target = ''
if tool.lower() in ('task', 'agent'):
    target = first(a, 'agent_type', 'subagent_type', 'agentType', 'agent', 'name')
elif first(a, 'command', 'cmd'):
    target = short_cmd(first(a, 'command', 'cmd'))
else:
    p = first(a, 'path', 'file_path', 'filePath', 'notebook_path', 'file')
    if p:
        target = os.path.basename(p.rstrip('/')) or p
    else:
        u = first(a, 'url')
        if u:
            target = re.sub(r'^[A-Za-z]+://', '', u).split('/')[0]
        else:
            target = first(a, 'pattern', 'query')

def clean(s, n=60):
    return re.sub(r'[\x00-\x1f]+', ' ', s).strip()[:n]

fields = [clean(x) or '-' for x in (event, tool, agent, target)]
fields.append(clean(first(d, 'cwd'), 1000) or '-')
print('\t'.join(fields))
PY

EV="-"; TOOL="-"; AGENT="-"; MAL="-"; CWD="-"
if [ -n "$PAYLOAD" ]; then
  if command -v python3 >/dev/null 2>&1; then
    rad=$(printf '%s' "$PAYLOAD" | python3 -c "$PROG" 2>/dev/null) || rad=""
    if [ -n "$rad" ]; then
      IFS='	' read -r EV TOOL AGENT MAL CWD <<EOF
$rad
EOF
    fi
  else
    # Without python3: pick the few fields we need with sed. Good enough for one line of JSON.
    falt() { printf '%s' "$PAYLOAD" | tr '\n' ' ' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1; }
    TOOL=$(falt 'tool_\{0,1\}[nN]ame'); AGENT=$(falt 'agent_\{0,1\}[tT]ype'); [ -n "$AGENT" ] || AGENT=$(falt 'agent_\{0,1\}[nN]ame')
    CWD=$(falt cwd); EV=$(falt hook_event_name)
    TOOL=${TOOL:--}; AGENT=${AGENT:--}; CWD=${CWD:--}; EV=${EV:--}
  fi
fi
case "$EV" in SubagentStart) EVENT=${EVENT:-start};; SubagentStop) EVENT=${EVENT:-done};; esac
[ "$EVENT" = stop ] && EVENT=done
[ -n "$HARNESS" ] || { [ -n "${CLAUDECODE:-}" ] && HARNESS=claude; }

# Which team: the folder projects/<team>/ the session runs in, otherwise the name in .board-name.
TEAM=""
[ "$CWD" != "-" ] && [ -d "$CWD" ] || CWD="$PWD"
CWD=$(cd "$CWD" 2>/dev/null && pwd -P) || CWD=""
case "$CWD" in
  "$R"/projects/*) rest=${CWD#"$R"/projects/}; TEAM=${rest%%/*};;
esac
if [ -z "$TEAM" ] && [ -s "$R/.board-name" ]; then TEAM=$(head -1 "$R/.board-name" | tr -d '\r\n'); fi
case "$TEAM" in ""|README.md|.*) exit 0;; esac
# Example names and the board's own names (lead, release, ...) are no team: the lead's own sessions stay out.
if grep -v '^[[:space:]]*#' "$R/tools/upptagna-namn.txt" 2>/dev/null | grep -qxF "$TEAM"; then exit 0; fi
T="$R/projects/$TEAM/.claude"

# ---------- small JSON helpers, pure bash ----------
jstr() { # one JSON string, at most $2 characters
  local s="$1"
  s=$(printf '%s' "$s" | tr -d '\000-\010\013-\037' | tr '\t\n' '  ')
  s="${s:0:${2:-60}}"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  printf '"%s"' "$s"
}
jlist() { # stdin: one name per line → ["a","b"] (at most 100)
  local first=1 line
  printf '['
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ $first = 1 ] || printf ','
    first=0; jstr "$line" 60
  done
  printf ']'
}
names() { # names <dir> [md]: the entries of a directory, without .md, skipping dotfiles and _template
  [ -d "$1" ] || return 0
  local f b
  for f in "$1"/*; do
    [ -e "$f" ] || continue
    b=${f##*/}
    case "$b" in .*|_template.md) continue;; esac
    if [ "${2:-}" = md ]; then [ -f "$f" ] || continue; case "$b" in *.md) ;; *) continue;; esac; fi
    printf '%s\n' "${b%.md}"
  done | head -100
}

lab() {
  local n=0 l=none
  [ -f "$T/agents/hr.md" ] && { n=$((n+1)); l=factory; }
  [ -d "$T/capabilities" ] && { n=$((n+1)); l=hive; }
  [ -d "$T/flux" ] && { n=$((n+1)); l=flux; }
  [ $n -gt 1 ] && l=mixed
  printf '%s' "$l"
}

formagor() { # capabilities with energy from the frontmatter
  local first=1 f b e
  printf '['
  if [ -d "$T/capabilities" ]; then
    for f in "$T/capabilities"/*.md; do
      [ -f "$f" ] || continue
      b=${f##*/}; case "$b" in _template.md|.*) continue;; esac
      [ $first = 1 ] || printf ','
      first=0
      e=$(sed -n '1,30{s/^energy:[[:space:]]*\([0-9][0-9]*\).*/\1/p;}' "$f" | head -1)
      if [ -n "$e" ]; then printf '{"namn":%s,"energi":%s}' "$(jstr "${b%.md}" 60)" "$e"
      else printf '{"namn":%s}' "$(jstr "${b%.md}" 60)"; fi
    done
  fi
  printf ']'
}

tidslinjer() { # FLUX: <evolution>/<timeline> when there are timelines, otherwise the evolution itself
  local d t h any
  [ -d "$T/flux/evolution" ] || return 0
  for d in "$T/flux/evolution"/*/; do
    [ -d "$d" ] || continue
    h=${d%/}; h=${h##*/}; any=0
    for t in "$d"timeline-*; do
      [ -d "$t" ] || continue
      any=1; printf '%s/%s\n' "$h" "${t##*/}"
    done
    [ $any = 1 ] || printf '%s\n' "$h"
  done | head -100
}

logg() { # the last 20 lines of the lab's evolution log, without comments and blank lines
  local f
  for f in "$T/evolution.log" "$T/flux/evolution.log"; do
    [ -f "$f" ] && grep -v '^[[:space:]]*#' "$f" | grep -v '^[[:space:]]*$' | tail -20
  done | tail -20 | while IFS= read -r line; do printf '%s\n' "${line:0:300}"; done
}

roster_json() {
  printf '{"team":%s,"lab":"%s","harness":%s,"roster":{' "$(jstr "$TEAM" 60)" "$(lab)" "$(jstr "${HARNESS:-unknown}" 20)"
  printf '"agents":%s,' "$(names "$T/agents" md | jlist)"
  printf '"kandidater":%s,' "$(names "$T/agents/candidates" md | jlist)"
  printf '"formagor":%s,' "$(formagor)"
  printf '"upplosta":%s,' "$(names "$T/dissolved" md | jlist)"
  printf '"tidslinjer":%s,' "$(tidslinjer | jlist)"
  printf '"vinnare":%s,' "$(names "$T/flux/winners" | jlist)"
  printf '"kyrkogard":%s' "$(names "$T/flux/graveyard" | jlist)"
  printf '},"logg":['
  local first=1 line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ $first = 1 ] || printf ','
    first=0; jstr "$line" 300
  done <<EOF
$(logg)
EOF
  printf ']}'
}

aktivitet_json() {
  local agent="$AGENT" verktyg="$TOOL" mal="$MAL"
  [ "$agent" = "-" ] && agent=main
  case "$EVENT" in
    start) verktyg=start; mal="-";;
    done)  verktyg=done; mal="-";;
  esac
  [ "$verktyg" = "-" ] && verktyg=unknown
  printf '{"team":%s,"agent":%s,"verktyg":%s' "$(jstr "$TEAM" 60)" "$(jstr "$agent" 60)" "$(jstr "$verktyg" 40)"
  [ "$mal" != "-" ] && printf ',"mal":%s' "$(jstr "$mal" 60)"
  printf '}'
}

send() { # send <path> <json>: in the background, at most 3 seconds, never a sound
  if [ "$TORR" = 1 ]; then printf 'POST %s%s\n%s\n' "${URL:-<.board-url>}" "$1" "$2"; return 0; fi
  local f
  f=$(mktemp "${TMPDIR:-/tmp}/agentpuls.XXXXXX" 2>/dev/null) || return 0
  printf '%s' "$2" > "$f"
  local fa="$f"
  command -v cygpath >/dev/null 2>&1 && fa=$(cygpath -w "$f")
  ( curl -sS -o /dev/null --max-time 3 -H 'Content-Type: application/json' --data-binary "@$fa" "$URL$1"; rm -f "$f" ) </dev/null >/dev/null 2>&1 &
}

# The roster goes out at session start, and at most every 30 seconds while the agent works, so that a
# new agent or a dissolved capability shows up without a new session.
STAMP="${TMPDIR:-/tmp}/agentpuls-$(id -u 2>/dev/null || echo 0)-$(printf '%s' "$R/$TEAM" | cksum | cut -d' ' -f1).stamp"
now=$(date +%s)
skicka_roster=0
if [ "$MODE" = lag ]; then
  skicka_roster=1
else
  sist=$(cat "$STAMP" 2>/dev/null || echo 0)
  case "$sist" in ''|*[!0-9]*) sist=0;; esac
  [ $((now - sist)) -ge 30 ] && skicka_roster=1
fi

# No tool and no subagent event (an empty or broken payload): nothing to say about activity.
if [ "$MODE" = aktivitet ] && { [ "$TOOL" != "-" ] || [ -n "$EVENT" ]; }; then send /api/aktivitet "$(aktivitet_json)"; fi
if [ $skicka_roster = 1 ]; then
  [ "$TORR" = 1 ] || printf '%s\n' "$now" > "$STAMP" 2>/dev/null
  send /api/lag "$(roster_json)"
fi
exit 0
