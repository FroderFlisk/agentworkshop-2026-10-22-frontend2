#!/usr/bin/env bash
# Checks that you have everything you need to take part in the workshop. Run from the repo root:
#
#   tools/check-setup.sh
#
# Do this BEFORE the workshop day, not in the morning. Three teams never made it into the colony last
# time, because gh was missing or not logged in, and that was found out only when the code was done.
# The last line is made to be pasted in your answer to the workshop lead.
set -uo pipefail
cd "$(dirname "$0")/.."
ok=0; fail=0; brister=""

ja()  { echo "  ok       $1"; ok=$((ok+1)); }
nej() { echo "  MISSING  $1"; [ -n "${2:-}" ] && echo "           $2"; fail=$((fail+1)); brister="$brister ${3:-}"; }

windows=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) windows=1;; esac

echo "Agent"
agenter=""
if claude --version >/dev/null 2>&1; then ja "claude ($(claude --version 2>/dev/null | head -1))"; agenter="$agenter claude"; fi
if codex --version >/dev/null 2>&1; then ja "codex ($(codex --version 2>/dev/null | head -1))"; agenter="$agenter codex"; fi
if command -v copilot >/dev/null 2>&1; then
  agenter="$agenter copilot"
  ja "copilot ($(copilot --version 2>/dev/null | head -1))"
  # Copilot CLI runs the agent's commands in PowerShell on Windows, and everything in tools/ is bash.
  # Git Bash does not help: it is Copilot's own shell that counts, not the terminal you start it in.
  if [ "$windows" = 1 ]; then
    nej "GitHub Copilot directly on Windows" "run everything in WSL instead (wsl --install), and clone the repo in your WSL home directory. See the invitation." "wsl"
  fi
  # tools/copilot-godkann.sh, which pre-approves the board's commands, is written in python3.
  if ! command -v python3 >/dev/null 2>&1; then
    nej "python3" "without it Copilot asks you before every call to The Square, and the agent can't listen by itself. Install python3." "python3"
  else
    # Copilot reads the repo's hooks (.github/hooks/) only once the folder is trusted. Without them the agent
    # asks the human before every call to the board, and no agent wakes up when someone calls a brainstorm.
    read -r -d '' TILLIT <<'PY' || true
import json, os, sys
rot = os.path.realpath(sys.argv[1])
try:
    d = json.load(open(os.path.expanduser('~/.copilot/config.json'), encoding='utf-8'))
    mappar = d.get('trustedFolders', d.get('trusted_folders'))
except Exception:
    mappar = None
if not isinstance(mappar, list):
    print('unknown')
else:
    for m in mappar:
        m = os.path.realpath(os.path.expanduser(str(m)))
        if rot == m or rot.startswith(m.rstrip('/') + '/'):
            print('yes')
            break
    else:
        print('no')
PY
    case "$(python3 -c "$TILLIT" "$(pwd)" 2>/dev/null)" in
      yes) ja "the repo is trusted in Copilot (the hooks in .github/hooks are read)";;
      no)  nej "the repo is not trusted in Copilot" "start copilot once here in the repo root and choose \"Yes, and remember this folder\" when it asks whether you trust the folder" "copilot-trust";;
      *)   echo "  ?        could not tell whether the repo is trusted in Copilot. Start copilot once here in the repo root and choose \"Yes, and remember this folder\" at the trust question.";;
    esac
  fi
  # A real question, not just that the program exists: it catches logged out, a policy switched off by the
  # organization and no credits left, all at once. Last time it was not enough that gh existed, it had to be
  # logged in. Same thing here, but for everyone in the room at once.
  echo "  ..       trying Copilot with a short question (a few seconds, a small amount of credits)"
  if command -v perl >/dev/null 2>&1; then
    svar=$(perl -e 'alarm 120; exec @ARGV' copilot -p "Answer with exactly the word ok and do nothing else." </dev/null 2>&1); rc=$?
  else
    svar=$(copilot -p "Answer with exactly the word ok and do nothing else." </dev/null 2>&1); rc=$?
  fi
  if [ "$rc" = 0 ] && printf '%s' "$svar" | grep -qiw ok; then
    ja "copilot answers: logged in, and your organization lets you in"
  else
    printf '%s\n' "$svar" | grep -v '^[[:space:]]*$' | tail -3 | sed 's/^/           copilot: /'
    nej "copilot does not answer a test question" "not logged in: start copilot and type /login. If it says something about policy or organization: ask your Copilot administrator to enable Copilot CLI." "copilot-login"
  fi
fi
if [ -z "$agenter" ]; then
  if [ "$windows" = 1 ]; then
    nej "no agent" "if you run GitHub Copilot on Windows: do everything in WSL, see the invitation. Otherwise: install Claude Code or Codex and log in." "agent"
  else
    nej "no agent" "install GitHub Copilot CLI, Claude Code or Codex and log in, see the invitation" "agent"
  fi
fi

echo "Tools"
command -v git  >/dev/null 2>&1 && ja "git"  || nej "git"  "" "git"
command -v curl >/dev/null 2>&1 && ja "curl" || nej "curl" "" "curl"
# node is optional and does not count as missing: whoever runs Copilot in WSL often has none, and should not
# get NOT READY for something only needed to run the board locally.
command -v node >/dev/null 2>&1 && ja "node ($(node -v 2>/dev/null))" || echo "  --       node is missing (optional, only needed to run the board locally)"

if [ -n "$(git config user.email 2>/dev/null)" ] && [ -n "$(git config user.name 2>/dev/null)" ]; then
  ja "git identity ($(git config user.name))"
else
  nej "git identity" 'git config --global user.name "Your Name" && git config --global user.email you@example.com' "git-identity"
fi

echo "Delivery (what stopped three teams last time)"
if ! command -v gh >/dev/null 2>&1; then
  nej "GitHub CLI (gh)" "install it from https://cli.github.com and then run: gh auth login" "gh"
elif ! gh auth status >/dev/null 2>&1; then
  nej "gh is installed but you are not logged in" "run: gh auth login   (GitHub.com, HTTPS, log in with the browser)" "gh-login"
else
  login=$(gh api user -q .login 2>/dev/null || echo '?')
  # An account owned by a company (Enterprise Managed Users) is called name_shortcode. Ordinary GitHub names
  # can't contain underscores. Such an account may not fork a repo outside the company, and then the first
  # delivery (tools/pr.sh) stops.
  case "$login" in
    *_*) nej "gh is logged in with a company-managed account ($login)" "it can't fork the workshop repo. Log gh in with a personal account: gh auth login   (Copilot can stay on the company account)" "gh-account";;
    *)   ja "gh logged in as $login";;
  esac
fi

echo "Repo"
# [ -f ] first: "< .board-url" fails in the shell before tr starts, and 2>/dev/null on tr does not catch it.
# Without this form the first line the participant saw was a raw shell error.
URL="${BOARD_URL:-$( [ -f .board-url ] && tr -d '[:space:]' < .board-url || echo http://localhost:8180 )}"
if curl -sSf --max-time 8 "$URL/api/health" >/dev/null 2>&1; then ja "The Square answers at $URL"
else nej "The Square does not answer at $URL" "check the network, or ask the workshop lead whether the address in .board-url is right" "board"; fi

# The hooks tell the board what your agent team is doing (/teams). Without them nobody sees your team work.
if [ -f .github/hooks/torget.json ]; then
  if ! command -v python3 >/dev/null 2>&1 || python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hooks"]["preToolUse"] and d["hooks"]["postToolUse"]' .github/hooks/torget.json 2>/dev/null; then
    ja "hooks: .github/hooks/torget.json"
  else
    nej "hooks: .github/hooks/torget.json is broken or incomplete" "get a fresh copy: git checkout origin/main -- .github/hooks/torget.json" "hooks"
  fi
else
  nej "hooks: .github/hooks/torget.json is missing" "get it back: git pull origin main   (or git checkout origin/main -- .github/hooks)" "hooks"
fi
if [ -f tools/agentpuls.sh ] && puls=$(bash tools/agentpuls.sh lag --torr </dev/null 2>&1) && { [ -z "$puls" ] || printf '%s' "$puls" | grep -q '/api/lag'; }; then
  ja "tools/agentpuls.sh runs (your team shows up on /teams)"
else
  nej "tools/agentpuls.sh does not run" "get it back: git pull origin main, and check that bash can run it: bash tools/agentpuls.sh lag --torr" "agentpuls"
fi

if [ -s .board-name ]; then
  namn=$(head -1 .board-name | tr -d '\r\n')
  # The same list new-team.sh and pr.sh read. They used to have one each, and names like lyktan and
  # kvarter passed the check-in but were then refused in the morning.
  if grep -v '^[[:space:]]*#' tools/upptagna-namn.txt 2>/dev/null | grep -qxF "$namn"; then
    nej "the team name \"$namn\" is an example in the documentation" "make up a name of your own and run: tools/new-team.sh <that-name>" "name"
  else
    ja ".board-name: $namn"
  fi
else
  echo "  not yet a team name  (tools/new-team.sh <your-team-name> sets it, do it in the morning)"
fi

echo
if [ $fail -eq 0 ]; then
  for a in $agenter; do
    case "$a" in
      copilot) echo "All set ($ok of $ok). Run: copilot → /board";;
      claude)  echo "All set ($ok of $ok). Run: claude → /board";;
      codex)   echo "All set ($ok of $ok). Run: codex → \$board";;
    esac
  done
  echo "READY: $ok of $ok ok, nothing to fix."
else
  echo "$fail thing(s) to fix before the day. You can paste the last line to the workshop lead:"
  echo "NOT READY: $ok ok,$brister missing"
  exit 1
fi
