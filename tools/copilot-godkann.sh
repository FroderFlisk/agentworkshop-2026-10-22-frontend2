#!/usr/bin/env bash
# Pre-approval for GitHub Copilot CLI. Called by .github/hooks/torget.json before every tool call.
#
# Copilot does not read .claude/settings.json. Without this script the agent asks the human before every
# call to the board, and then no agent wakes up by itself when someone calls a brainstorm.
#
# Approves the same commands that .claude/settings.json allows, and only when the command stands alone:
# no chain, no pipe, no redirection, no command substitution. Everything else is left to Copilot, which
# asks the human as usual. The script never says no and always exits 0, because Copilot treats exit 2 or a
# crash as a no, and then every single shell command in the whole session is stopped.
#
# Copilot reads the hook only once the folder is trusted: start copilot once in the repo root and say yes.
# Try it yourself:  printf '%s' '{"toolName":"bash","toolArgs":"{\"command\":\"tools/board.sh read\"}"}' | tools/copilot-godkann.sh
set -u

# read -d '' instead of PROG=$(cat <<'PY' ...): bash 3.2 looks for quotes inside a heredoc in $(...),
# trips over the backtick in the regex and dies with exit 2, which is a no to everything.
read -r -d '' PROG <<'PY' || true
import json, re, sys

try:
    d = json.load(sys.stdin)
    namn = d.get('toolName') or d.get('tool_name') or ''
    if namn.lower() not in ('bash', 'shell'):
        sys.exit(0)
    a = d.get('toolArgs', d.get('tool_input', {}))
    if isinstance(a, str):
        a = json.loads(a)
    cmd = (a or {}).get('command', '').strip()
except Exception:
    sys.exit(0)

# Characters that can start a second command, write to a file or run code inside the arguments.
# If any of them is present, even inside quotes, the human decides.
if not cmd or re.search(r'[;&|<>`$\\\n\r]', cmd):
    sys.exit(0)

# From a team folder (projects/<name>/) the scripts are ../../tools/..., from the repo root tools/...
P = r'(?:bash |sh )?(?:\./|(?:\.\./)+)?'
TILLATNA = [
    P + r'tools/board\.sh(?: .*)?',
    P + r'tools/spore\.sh(?: .*)?',
    P + r'tools/agentpuls\.sh(?: .*)?',
    P + r'tools/check-setup\.sh',
    P + r'tools/new-team\.sh(?: .*)?',
    P + r'tools/pr\.sh(?: .*)?',
    P + r'tools/release\.sh (?:list|glomda.*|stale.*|check .*|diff .*)',
    r'node (?:\./|(?:\.\./)+)?board/(?:server\.js|test\.mjs)',
    r'gh pr (?:list|view|diff)(?: .*)?',
    r'git (?:status|log|diff|pull)(?: .*)?',
]
if not any(re.fullmatch(m, cmd) for m in TILLATNA):
    sys.exit(0)

# git can run programs and write files through flags. Such things are never approved in advance.
if re.search(r'--(?:upload-pack|receive-pack|exec|output|ext-diff|config)', cmd):
    sys.exit(0)

# board.sh --fil/--file and spore.sh --file post the contents of a file on the board, where everyone in
# the room sees it. Approved only for files in /tmp or a .txt/.md file in the working directory, never
# anything with .. or a home directory.
m = re.search(r'--fil(?:e)?\s+(\S+)', cmd)
if m:
    fil = m.group(1).strip('\'"')
    if '..' in fil or not re.fullmatch(r'/tmp/[A-Za-z0-9._-]+|[A-Za-z0-9._-]+\.(?:txt|md)', fil):
        sys.exit(0)

print(json.dumps({'permissionDecision': 'allow',
                  'permissionDecisionReason': 'workshop tool, same list as .claude/settings.json'}))
PY

indata=$(cat)
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$indata" | python3 -c "$PROG" 2>/dev/null || true
fi
exit 0
