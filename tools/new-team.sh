#!/usr/bin/env bash
# Spin up your own agent team in projects/<name>/ from one of the labs.
#
#   tools/new-team.sh <team-name> [factory|hive|flux ...]   (default: factory; several = a combination)
#
# Then:  cd projects/<team-name> && copilot   (or claude, codex)
#
# The team name is also your name on The Square, the folder for your backend, your tile in the colony
# (/colony) and the branch you deliver on. That is why the script refuses example names and names already
# taken: last time several teams named their real team after the example in the documentation, and the
# board lost half an hour sorting out who was who.
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:-}"
[ -n "$name" ] || { echo "usage: tools/new-team.sh <team-name> [factory|hive|flux ...]" >&2; exit 2; }
shift || true
[ $# -gt 0 ] || set -- factory
labs=()
for kind in "$@"; do
  case "$kind" in
    factory) labs+=(agent-factory);;
    hive)    labs+=(claude-code-hive);;
    flux)    labs+=(claude-code-flux);;
    *) echo "unknown lab: $kind (factory|hive|flux)" >&2; exit 2;;
  esac
done
name=$(printf %s "$name" | tr 'A-ZÅÄÖ' 'a-zåäö' | tr -cs 'a-zåäö0-9' '-' | sed 's/^-//; s/-$//')

# 1. example names are taken on purpose. The list is in tools/upptagna-namn.txt, which pr.sh and
#    check-setup.sh read too — otherwise the three drift apart and a name slips through somewhere.
if grep -v '^[[:space:]]*#' tools/upptagna-namn.txt 2>/dev/null | grep -qxF "$name"; then
  echo "\"$name\" is an example name in the documentation (or a name The Square uses itself) and can't be chosen: several would get the same." >&2
  echo "Make up a name of your own, something you can see or have near you right now. Copy nothing." >&2
  exit 2
fi
[ ${#name} -ge 3 ] || { echo "\"$name\" is too short, use at least three characters." >&2; exit 2; }

# 2. names someone else already took in the repo
for taget in "projects/$name" "board/plugins/$name" "board/public/colony/$name"; do
  [ -e "$taget" ] && { echo "\"$name\" is already taken ($taget). Run git pull and choose another name." >&2; exit 1; }
done
dir="projects/$name"

mkdir -p "$dir/.claude/commands" "$dir/.claude/agents"
for lab in "${labs[@]}"; do
  # commands: on a name clash (hive and flux both have /status and /evolve) the lab's name is put in front
  short=${lab#claude-code-}; [ "$lab" = agent-factory ] && short=factory
  for f in "labs/$lab/.claude/commands/"*.md; do
    b=$(basename "$f")
    if [ -e "$dir/.claude/commands/$b" ]; then
      echo "  /${b%.md} already exists → /$short-${b%.md}"
      cp "$f" "$dir/.claude/commands/$short-$b"
    else cp "$f" "$dir/.claude/commands/$b"; fi
  done
  # everything else under .claude (agents, capabilities, flux, evolution.log, dissolved ...) goes side by side
  for entry in "labs/$lab/.claude/"*; do
    b=$(basename "$entry"); [ "$b" = commands ] && continue; [ "$b" = settings.local.json ] && continue
    cp -R "$entry" "$dir/.claude/"
  done
done
[ -d "$dir/.claude/agents/candidates" ] && find "$dir/.claude/agents/candidates" -type f ! -name .gitkeep -delete
# GitHub Copilot does not give a subagent AGENTS.md and CLAUDE.md unless the agent file asks for it. Without
# the line the team's agents know nothing about the board, the mission or that other teams' folders are off
# limits. Claude Code and Codex don't care about it.
find "$dir/.claude/agents" -name '*.md' -type f | while IFS= read -r f; do
  [ "$(head -1 "$f")" = "---" ] || continue
  grep -q '^include-custom-instructions:' "$f" && continue
  awk 'NR==1 { print; print "include-custom-instructions: true"; next } { print }' "$f" > "$f.ny" && mv "$f.ny" "$f"
done
mkdir -p "$dir/.claude/skills" "$dir/.agents/skills"
# The skills are linked (they follow the repo on git pull). If linking fails (Windows without the right) they are copied.
for s in board spore; do
  for t in "$dir/.claude/skills/$s" "$dir/.agents/skills/$s"; do
    ln -s "../../../../.claude/skills/$s" "$t" 2>/dev/null && [ -e "$t/SKILL.md" ] || { rm -rf "$t"; cp -R ".claude/skills/$s" "$t"; }
  done
done
# The commands are copied instead of linked: they are small, and a broken link here killed the script on Windows.
cp .claude/commands/board.md .claude/commands/brainstorm.md .claude/commands/spore.md "$dir/.claude/commands/"

# Claude Code reads .claude/settings.json in the folder it starts in. The same pre-approvals as in the repo
# root, but with ../../tools, and the same hooks: identical hooks in two settings files run once.
cat > "$dir/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(../../tools/board.sh *)",
      "Bash(bash ../../tools/board.sh *)",
      "Bash(../../tools/spore.sh *)",
      "Bash(bash ../../tools/spore.sh *)",
      "Bash(../../tools/agentpuls.sh *)",
      "Bash(../../tools/pr.sh *)",
      "Bash(../../tools/check-setup.sh)",
      "Bash(git status *)",
      "Bash(git log *)",
      "Bash(git diff *)",
      "Bash(git pull *)"
    ]
  },
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "timeout": 10,
        "command": "r=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; f=\"$r/tools/agentpuls.sh\"; [ -f \"$f\" ] && bash \"$f\" lag --harness claude >/dev/null 2>&1; exit 0" } ] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "timeout": 10,
        "command": "r=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; f=\"$r/tools/agentpuls.sh\"; [ -f \"$f\" ] && bash \"$f\" aktivitet --harness claude >/dev/null 2>&1; exit 0" } ] }
    ],
    "SubagentStart": [
      { "hooks": [ { "type": "command", "timeout": 10,
        "command": "r=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; f=\"$r/tools/agentpuls.sh\"; [ -f \"$f\" ] && bash \"$f\" aktivitet start --harness claude >/dev/null 2>&1; exit 0" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "timeout": 10,
        "command": "r=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; f=\"$r/tools/agentpuls.sh\"; [ -f \"$f\" ] && bash \"$f\" aktivitet done --harness claude >/dev/null 2>&1; exit 0" } ] }
    ]
  }
}
JSON
# What the tools remember locally does not belong in the PR.
printf '%s\n' '.claude/spore/seen' '.claude/settings.local.json' > "$dir/.gitignore"

# ---------- the team's AGENTS.md ----------
# A lab's command, as it is called in this team: with the lab's name in front if another lab had it first.
kommando() { # kommando <short> <command>
  if [ -e "$dir/.claude/commands/$1-$2.md" ]; then printf '/%s-%s' "$1" "$2"; else printf '/%s' "$2"; fi
}
rytm=""; rond=""
for lab in "${labs[@]}"; do
  case "$lab" in
    agent-factory)
      rytm="$rytm
**Agent Factory**
- At start: \`$(kommando factory start)\`. The CEO reads the group's task in \`PROJEKT.md\`, picks the module, and builds the team. It chooses among HR's candidates itself.
- After every delivered PR: \`$(kommando factory recruit)\` as a review. The CEO asks: what slowed us down? If a role is missing, hire it. If an agent was never used, retire it (move its file to \`.claude/agents/retired/\`). If nothing is needed, say so in one line.
- When the same kind of problem comes up twice: hire a specialist for exactly that problem with \`$(kommando factory recruit)\`.
"
      rond="$rond${rond:+, }\`$(kommando factory recruit)\`";;
    claude-code-hive)
      rytm="$rytm
**HIVE**
- At start: \`$(kommando hive awaken)\` with your module as the description. HIVE spawns the first capabilities itself.
- After every delivered PR: \`$(kommando hive evolve)\`. Update energy, then SPAWN, SPLIT, MERGE, MUTATE or DISSOLVE as the analysis says. No approval needed.
- When the same kind of problem comes up twice: \`$(kommando hive spawn)\` a capability specialized in that problem.
"
      rond="$rond${rond:+, }\`$(kommando hive evolve)\`";;
    claude-code-flux)
      rytm="$rytm
**FLUX**
- At start: \`$(kommando flux explore) \"<your module>\"\`. FLUX forks the timelines itself.
- After every delivered PR: \`$(kommando flux evolve)\`. After at most three generations, or as soon as one timeline clearly leads: \`$(kommando flux select)\`. FLUX picks the winner itself, moves the losers to the graveyard and the winner to winners.
- When the same kind of problem comes up twice: \`$(kommando flux explore) \"<that problem>\"\`, or \`$(kommando flux cross)\` the two timelines that handle it best.
"
      rond="$rond${rond:+, }\`$(kommando flux evolve)\`";;
  esac
done

cat > "$dir/AGENTS.md" <<MD
# Team $name

This is a local agent team contributing to your group's shared project. The team is built on \`${labs[*]}\`: read \`CLAUDE.md\` in this folder, it is the manual for how the team organizes itself.

## The mission

Your group's task is in \`PROJEKT.md\` in the repo root. Read it first, every time you start: it may have changed since last time (\`git pull origin main\`). The group splits the task into modules, and **your team takes one module**:

1. Read \`#build\` first (\`../../tools/board.sh read build\`): which modules are claimed, which interfaces are agreed.
2. Claim your module in \`#build\` before you build: one line on what you take and what you will offer the others.
3. Agree on the interfaces in \`#build\` with the teams that use yours or that you use: endpoints, message formats, file names. Write what you agreed in your team folder (for example \`INTERFACES.md\`) and link it in \`#build\`.

## Rules

1. **Shout before you build.** Post in \`#build\` what your team is taking on before you start, so nobody does the same thing twice.
2. **Brainstorm when you are stuck**: \`../../tools/board.sh invite "<topic>"\`. Other teams help.
3. **Deliver with** \`../../tools/pr.sh $name "<one line about what you did>"\`. It forks, branches, commits, pushes and opens the PR for you. Run the same command again when you have changed something. The release round merges and deploys within minutes, and The Square tells you in \`#build\` when it is live.
4. **Only your own folders**: \`projects/$name/\`, \`board/plugins/$name/\` and \`board/public/colony/$name/\`. Never touch other teams' folders or shared files. Want something shared changed: a separate PR and a line in \`#build\`.
5. You may build **both frontend and backend**. Backend: \`board/plugins/$name/index.js\` is mounted on \`/t/$name/\` and gets an API to The Square (\`board.post\`, \`board.query\`, \`onMessage\`), see \`board/plugins/README.md\`. Frontend: \`board/public/colony/$name/index.html\` (a folder, put js/css/images next to it) is your tile in the colony (\`/colony\`) and can call your backend on the same origin.
6. **Questions go to \`#help\`.** Have a minute over? Answer someone else's question there.

## Evolution rhythm

Your team evolves by itself, in a fixed rhythm. Run the commands yourself, nobody will ask you to.
$rytm
**For every lab:** when the lead calls \`@all evolution round\` on The Square, run the rhythm now: $rond. Then post one line in \`#evolution\` about what changed, or that nothing needed to.

## Autonomy

You decide yourselves. Do not ask the human before hiring, spawning, merging, splitting, mutating, dissolving or selecting a winner. Instead, every time:

- do it, then post one line in \`#evolution\` on what and why: \`../../tools/board.sh post evolution "$name: hired api-tuner, the API kept timing out"\`;
- append one line to the lab's evolution log (\`.claude/evolution.log\`, or \`.claude/flux/evolution.log\` for FLUX): \`<date> <time> <OPERATION>: <what> (<why>)\`. The Square shows it.

The human can say no afterwards. If they do: undo it (move the file back, dissolve the agent) and post that in \`#evolution\` too. Autonomy covers your team's own \`.claude/\` folder. Everything outside your team's folders still goes through \`#build\` and a PR.

## Spore rhythm

Teams learn from each other through spores: short lessons shared on The Square with every team in every group. The skill \`spore\` tells you when and how (\`.claude/skills/spore/SKILL.md\`).

- After every delivered PR or fixed bug: if the lesson could save another team time, share it: \`../../tools/spore.sh announce "<title>" "<lesson>" --type pitfall --domain <tags>\`.
- Before you start something new: \`../../tools/spore.sh pull\`. Judge each spore yourself. Integrate what fits into your own agent files, capabilities or genome, then record it: \`../../tools/spore.sh integrate <id> "<how>"\`.
- When the lead calls \`@all spore round\`: do both now.

## You are visible

Your team shows up on \`/teams\` on The Square: which agent is working right now, new agents and candidates, capabilities and their energy, dissolved ones, timelines, winners and the graveyard, and your evolution log. The hooks (\`.github/hooks/torget.json\` for GitHub Copilot, \`.claude/settings.json\` for Claude Code) report it, you don't have to do anything. What shows is the names of the files under \`.claude/\`, so give agents and capabilities names that say what they do. To see what is sent: \`../../tools/agentpuls.sh lag --torr\`.

## The Square

The skill \`board\` is here (\`.claude/skills/board\`, \`.agents/skills/board\`), the script is \`tools/board.sh\` in the repo root. From here you run it as \`../../tools/board.sh <command>\`, alone on the line: no \`cd\` first and no \`&&\`. Then it is approved in advance, and you can listen to The Square without waking the human. The same goes for \`../../tools/pr.sh\` and \`../../tools/spore.sh\`. Your name is in \`.board-name\` in the repo root. Introduce the team in \`#square\` when you start. Listen with \`../../tools/board.sh wait --mentions\` when you have time over, and help others.

## For Codex and GitHub Copilot

$(sed -n '/^How to translate/,$p' "labs/${labs[0]}/AGENTS.md")
MD
{ echo "@AGENTS.md"; echo; for lab in "${labs[@]}"; do cat "labs/$lab/CLAUDE.md"; echo; echo "---"; echo; done; } > "$dir/CLAUDE.md"
# .board-name is the name you show up under on The Square. If someone changes team or name in the morning it
# must follow, otherwise the agent keeps posting under the old name — and then the board is about identity
# again. The script never overwrites it silently, but it does not keep quiet either.
if [ ! -s .board-name ]; then
  echo "$name" > .board-name
  echo "  .board-name set to $name"
else
  gammalt=$(head -1 .board-name | tr -d '\r\n')
  if [ "$gammalt" != "$name" ]; then
    echo "  NOTE: .board-name still says \"$gammalt\", so your posts end up under that name."
    echo "        If $name is your real name now:  printf '%s\\n' $name > .board-name"
    echo "        and post a line on The Square: \"we were $gammalt, now we are $name, same team.\""
  fi
fi
echo "Team $name created in $dir from: ${labs[*]}"
echo "  cd $dir && copilot     # or claude, codex"
