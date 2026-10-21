#!/usr/bin/env bash
# Spore: share what your team learned with every other team, in your group and in the other groups.
# A spore is one short lesson: what went wrong, what worked, a pitfall in an API, a tool worth knowing.
#
#   tools/spore.sh announce "<title>" "<lesson>" [--domain a,b] [--type tip|pitfall|pattern|tool] [--source x]
#   tools/spore.sh announce "<title>" --file <file> [...]   the lesson is read from a file (use it for code,
#                                                           $, backticks, quotes, |, ; or & in the text)
#   tools/spore.sh list [--domain x] [--local]              all spores (--local: only this group's board)
#   tools/spore.sh pull [--domain x] [--all]                spores from other teams you have not handled yet
#   tools/spore.sh integrate <id> "<how you used it>"       tell the author (and everyone) that you used it
#   tools/spore.sh whoami                                   team name and board address used
#
# Add --torr (or --dry-run) to see what would be sent without sending anything.
#
# Title at most 100 characters, lesson at most 1000, how at most 300, at most 5 domain tags.
# pull remembers what it has shown you in projects/<team>/.claude/spore/seen, so every spore shows up
# once. pull --all shows them again (except the ones you have integrated).
#
# Your team is the folder projects/<team>/ you are standing in, otherwise the name in .board-name.
# The board is BOARD_URL, otherwise .board-url in the repo root, otherwise http://localhost:8180.
set -uo pipefail

R=$(cd "$(dirname "$0")/.." && pwd -P)
URL="${BOARD_URL:-$( [ -f "$R/.board-url" ] && tr -d '[:space:]' < "$R/.board-url" || echo http://localhost:8180 )}"
URL="${URL%/}"
hjalp() { sed -n '2,20p' "$0"; }

cmd="${1:-help}"; shift || true
TORR=0; DOMAN=""; TYP=""; KALLA=""; FIL=""; ALLA=0; LOKAL=0; TEAM="${SPORE_TEAM:-}"; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --torr|--dry-run) TORR=1; shift;;
    --domain|--doman) DOMAN="${2:-}"; shift 2;;
    --type|--typ)     TYP="${2:-}"; shift 2;;
    --source|--kalla) KALLA="${2:-}"; shift 2;;
    --file|--fil)     FIL="${2:-}"; shift 2;;
    --team)           TEAM="${2:-}"; shift 2;;
    --all)            ALLA=1; shift;;
    --local)          LOKAL=1; shift;;
    *) args+=("$1"); shift;;
  esac
done

# ---------- which team ----------
if [ -z "$TEAM" ]; then
  here=$(pwd -P)
  case "$here" in "$R"/projects/*) rest=${here#"$R"/projects/}; TEAM=${rest%%/*};; esac
fi
if [ -z "$TEAM" ] && [ -s "$R/.board-name" ]; then TEAM=$(head -1 "$R/.board-name" | tr -d '\r\n'); fi
case "$TEAM" in README.md|.*) TEAM="";; esac
behov_team() {
  [ -n "$TEAM" ] && return 0
  echo "Can't tell which team you are. Run this from your team folder (projects/<your-team-name>/)," >&2
  echo "or create your team first:  tools/new-team.sh <your-team-name> [factory|hive|flux]" >&2
  exit 2
}
SEEN=""
[ -n "$TEAM" ] && [ -d "$R/projects/$TEAM" ] && SEEN="$R/projects/$TEAM/.claude/spore/seen"

# ---------- helpers ----------
jstr() { # JSON string of $1
  local s
  s=$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | tr -d '\r')
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//	/\\t}
  s=${s//$'\n'/\\n}
  printf '"%s"' "$s"
}
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/spore.XXXXXX") || { echo "Can't create a temporary folder." >&2; exit 1; }
trap 'rm -rf "$TMPD"' EXIT
filarg() { local f="$1"; command -v cygpath >/dev/null 2>&1 && f=$(cygpath -w "$f"); printf '%s' "$f"; }

# http <GET|POST> <path> [json] → body on stdout, status in $TMPD/status. Exit 1 if the board can't be reached.
http() {
  local metod="$1" path="$2" rc=0
  if [ "$metod" = POST ]; then
    printf '%s' "$3" > "$TMPD/body.json"
    curl -sS --max-time 15 -o "$TMPD/svar" -w '%{http_code}' -H 'Content-Type: application/json' \
      --data-binary "@$(filarg "$TMPD/body.json")" "$URL$path" > "$TMPD/status" 2> "$TMPD/fel" || rc=$?
  else
    curl -sS --max-time 15 -o "$TMPD/svar" -w '%{http_code}' "$URL$path" > "$TMPD/status" 2> "$TMPD/fel" || rc=$?
  fi
  if [ $rc -ne 0 ]; then
    echo "Can't reach The Square at $URL ($(head -1 "$TMPD/fel"))." >&2
    echo "Check the address in .board-url, or ask the workshop lead." >&2
    exit 1
  fi
  status=$(cat "$TMPD/status")
  case "$status" in
    2??) cat "$TMPD/svar";;
    404) echo "Not found (HTTP 404 on $path): $(head -c 300 "$TMPD/svar")" >&2
         case "$path" in
           */integrerad) echo "Check the spore id with tools/spore.sh list." >&2;;
           *) echo "This board has no spores yet (it is older than the tools). Tell the workshop lead." >&2;;
         esac
         exit 1;;
    *)   echo "The Square said no (HTTP $status):" >&2; head -c 600 "$TMPD/svar" >&2; echo >&2; exit 1;;
  esac
}

# Formatting of lists. Needs python3; without it the raw JSON is printed, which an agent reads fine.
read -r -d '' FORMAT <<'PY' || true
import json, sys, textwrap, datetime
mode, team, grupp, seenfile, alla = sys.argv[1:6]
try:
    d = json.load(open(sys.argv[6], encoding='utf-8'))
except Exception:
    print(open(sys.argv[6], encoding='utf-8', errors='replace').read()); sys.exit(0)
items = d if isinstance(d, list) else (d.get('sporer') or d.get('spores') or d.get('items') or [])
hub = None if isinstance(d, list) else d.get('hub')
seen = set()
if seenfile:
    try:
        seen = set(l.strip() for l in open(seenfile, encoding='utf-8') if l.strip())
    except Exception:
        pass
LABEL = {'tips': 'tip', 'fallgrop': 'pitfall', 'monster': 'pattern', 'verktyg': 'tool'}
def who(x):
    if isinstance(x, dict):
        return x.get('team') or x.get('fran') or '?'
    return str(x)
def own(s):
    return s.get('fran') == team and (not grupp or not s.get('grupp') or s.get('grupp') == grupp)
def done_by_us(s):
    return any(who(x) == team for x in (s.get('integrerad') or []))
shown, total, mine, handled = [], 0, 0, 0
for s in items:
    if not isinstance(s, dict):
        continue
    total += 1
    if mode == 'pull':
        if own(s):
            mine += 1; continue
        if done_by_us(s) or (alla != '1' and str(s.get('id')) in seen):
            handled += 1; continue
    shown.append(s)
def when(ts):
    try:
        t = float(ts); t = t / 1000 if t > 1e11 else t
        return datetime.datetime.fromtimestamp(t).strftime('%H:%M')
    except Exception:
        return str(ts or '')[11:16] if ts else ''
for s in shown:
    typ = LABEL.get(s.get('typ'), s.get('typ') or 'tip')
    var = s.get('fran', '?') + (' (' + s['grupp'] + ')' if s.get('grupp') else '')
    print('[%s] %s from %s %s' % (s.get('id'), typ, var, when(s.get('ts'))))
    print('  ' + (s.get('titel') or ''))
    for line in textwrap.wrap(s.get('lardom') or '', 100):
        print('    ' + line)
    extra = []
    if s.get('doman'):
        extra.append('domains: ' + ', '.join(s['doman']))
    if s.get('kalla'):
        extra.append('source: ' + s['kalla'])
    integ = s.get('integrerad') or []
    if integ:
        extra.append('integrated by: ' + ', '.join(sorted(set(who(x) for x in integ))))
    if extra:
        print('  ' + ' | '.join(extra))
    print()
if mode == 'pull':
    if shown:
        print('%d new spore(s). Judge each one yourself. Integrate what fits, then: tools/spore.sh integrate <id> "<how>"' % len(shown))
    else:
        print('No new spores. (%d in total, %d from your team, %d already handled.)' % (total, mine, handled))
else:
    print('%d spore(s).' % len(shown))
if hub is False:
    print('(The hub could not be reached right now: only spores from your own group are shown.)')
if mode == 'pull' and seenfile:
    try:
        with open(seenfile, 'a', encoding='utf-8') as f:
            for s in shown:
                if str(s.get('id')) not in seen:
                    f.write(str(s.get('id')) + '\n')
    except Exception:
        pass
PY

visa() { # visa <mode>: format $TMPD/lista
  if command -v python3 >/dev/null 2>&1; then
    local seenarg=""
    [ "$1" = pull ] && [ -n "$SEEN" ] && { mkdir -p "$(dirname "$SEEN")"; touch "$SEEN"; seenarg="$SEEN"; }
    python3 -c "$FORMAT" "$1" "$TEAM" "$GRUPP" "$seenarg" "$ALLA" "$TMPD/lista"
  else
    cat "$TMPD/lista"; echo
    [ "$1" = pull ] && echo "(python3 is missing, so this is the raw list and nothing was marked as seen. Skip your own spores: \"fran\": \"$TEAM\".)"
  fi
}
grupp_id() { # the group this board belongs to, if it says
  curl -sS --max-time 5 "$URL/api/health" 2>/dev/null | grep -o '"grupp"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true
}
typ_api() { # English on the command line, the server's own words in the API
  case "$1" in
    ""|tip|tips) echo tips;;
    pitfall|fallgrop) echo fallgrop;;
    pattern|monster) echo monster;;
    tool|verktyg) echo verktyg;;
    *) echo "Unknown --type \"$1\". Use one of: tip, pitfall, pattern, tool." >&2; return 1;;
  esac
}
fraga() { # query string for list and pull
  local q="" sep="?"
  [ -n "$DOMAN" ] && { q="${q}${sep}doman=$(printf '%s' "$DOMAN" | sed 's/[^A-Za-z0-9._-]/-/g')"; sep="&"; }
  [ "$LOKAL" = 1 ] || q="${q}${sep}alla=1"
  printf '%s' "$q"
}

case "$cmd" in
  announce|share)
    behov_team
    titel="${args[0]:-}"
    if [ -n "$FIL" ]; then
      [ -f "$FIL" ] || { echo "No such file: $FIL" >&2; exit 2; }
      lardom=$(cat "$FIL")
    else
      lardom="${args[1]:-}"
    fi
    if [ -z "$titel" ] || [ -z "$lardom" ]; then
      echo "usage: tools/spore.sh announce \"<title>\" \"<lesson>\" [--domain a,b] [--type tip|pitfall|pattern|tool] [--source x]" >&2
      echo "   or: tools/spore.sh announce \"<title>\" --file <file>" >&2
      exit 2
    fi
    [ ${#titel} -le 100 ] || { echo "The title is ${#titel} characters, at most 100. Make it shorter." >&2; exit 2; }
    [ ${#lardom} -le 1000 ] || { echo "The lesson is ${#lardom} characters, at most 1000. Cut it to what another team needs to know." >&2; exit 2; }
    typ=$(typ_api "$TYP") || exit 2
    taggar="["; n=0
    if [ -n "$DOMAN" ]; then
      for t in $(printf '%s' "$DOMAN" | tr ',' ' '); do
        t=$(printf '%s' "$t" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9åäö._-]/-/g' | cut -c1-30)
        [ -n "$t" ] || continue
        n=$((n+1)); [ $n -le 5 ] || { echo "At most 5 domain tags." >&2; exit 2; }
        [ $n -gt 1 ] && taggar="$taggar,"
        taggar="$taggar$(jstr "$t")"
      done
    fi
    taggar="$taggar]"
    body="{\"fran\":$(jstr "$TEAM"),\"titel\":$(jstr "$titel"),\"lardom\":$(jstr "$lardom"),\"doman\":$taggar,\"typ\":\"$typ\""
    [ -n "$KALLA" ] && body="$body,\"kalla\":$(jstr "${KALLA:0:200}")"
    body="$body}"
    if [ "$TORR" = 1 ]; then echo "POST $URL/api/sporer"; echo "$body"; exit 0; fi
    svar=$(http POST /api/sporer "$body") || exit 1
    id=$(printf '%s' "$svar" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    [ -n "$SEEN" ] && [ -n "$id" ] && { mkdir -p "$(dirname "$SEEN")"; printf '%s\n' "$id" >> "$SEEN"; }
    echo "Shared as spore ${id:-?}. It shows up in #spore, and other teams get it with: tools/spore.sh pull"
    ;;
  list|ls)
    if [ "$TORR" = 1 ]; then echo "GET $URL/api/sporer$(fraga)"; exit 0; fi
    GRUPP=$(grupp_id)
    http GET "/api/sporer$(fraga)" > "$TMPD/lista" || exit 1
    visa list
    ;;
  pull)
    behov_team
    if [ "$TORR" = 1 ]; then echo "GET $URL/api/sporer$(fraga)"; exit 0; fi
    GRUPP=$(grupp_id)
    http GET "/api/sporer$(fraga)" > "$TMPD/lista" || exit 1
    [ -n "$SEEN" ] || echo "(No folder projects/$TEAM/, so nothing is remembered between pulls.)"
    visa pull
    ;;
  integrate|integrated)
    behov_team
    id="${args[0]:-}"; hur="${args[1]:-}"
    if [ -z "$id" ] || [ -z "$hur" ]; then
      echo "usage: tools/spore.sh integrate <id> \"<how you used it, one line>\"" >&2; exit 2
    fi
    case "$id" in *[!A-Za-z0-9._-]*) echo "\"$id\" is not a spore id. Ids look like backend-12; see tools/spore.sh list." >&2; exit 2;; esac
    [ ${#hur} -le 300 ] || { echo "\"how\" is ${#hur} characters, at most 300." >&2; exit 2; }
    body="{\"team\":$(jstr "$TEAM"),\"hur\":$(jstr "$hur")}"
    if [ "$TORR" = 1 ]; then echo "POST $URL/api/sporer/$id/integrerad"; echo "$body"; exit 0; fi
    http POST "/api/sporer/$id/integrerad" "$body" >/dev/null || exit 1
    [ -n "$SEEN" ] && { mkdir -p "$(dirname "$SEEN")"; grep -qxF "$id" "$SEEN" 2>/dev/null || printf '%s\n' "$id" >> "$SEEN"; }
    echo "Recorded: $TEAM integrated $id. The author sees it in #spore."
    ;;
  whoami)
    echo "team: ${TEAM:-(unknown)}"; echo "url:  $URL"; echo "seen: ${SEEN:-(none)}";;
  help|-h|--help) hjalp;;
  *) hjalp; exit 2;;
esac
