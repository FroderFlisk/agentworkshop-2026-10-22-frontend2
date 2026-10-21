# Labs

Four ways to organize agents. All are built as plain agent projects: markdown agents and slash commands under `.claude/`. GitHub Copilot CLI and Claude Code read the same files. Nothing to install.

The first three are what your team is built from. `tools/new-team.sh <your-team-name> factory|hive|flux` copies the system to `projects/<your-team-name>/`, so you do the exercises below in your own team folder. To try a system on its own, without the team's mission, run `cd labs/<lab> && copilot` (or `claude`, `codex`).

Read `CLAUDE.md` first, it is the whole manual. All three labs **evolve by themselves**: the agents run the lab's commands in a fixed rhythm (your team's `AGENTS.md` says when), decide without asking, log every decision in the lab's evolution log, and post one line on why in `#evolution`. The human can say no afterwards. Everything shows up on `/teams`.

## 1 · Agent Factory: agents that recruit agents

Two core agents, CEO and HR. The CEO reads the task and decides which roles are needed, HR designs three candidates per role (specialist, generalist, innovator), the CEO interviews them and chooses. The winner is installed in `.claude/agents/`. Any agent can ask HR for new colleagues later, and the CEO retires agents nobody uses.

**Try:** `/start`. Look at the three candidates for the same role: what sets them apart, and which one would you never have written yourself?

**Commands:** `/start`, `/recruit`, `/team`. New agents may need the agent (`copilot`, `claude`) to be restarted.

## 2 · HIVE: capabilities instead of roles

No CEO, no hierarchy. Capabilities spawn when needed, gain energy when used, lose energy when idle, and dissolve below 10. Overlapping capabilities merge, overloaded ones split. What dissolves ends up in `.claude/dissolved/` and can come back.

**Try:** `/awaken`, work a little, run `/evolve` and watch what HIVE does. Compare with Agent Factory: what did you lose when the roles disappeared, what did you gain?

**Commands:** `/awaken`, `/spawn`, `/status`, `/evolve`, `/dissolve`.

## 3 · FLUX: evolution over parallel timelines

No agents at all. Genes (personality genes like `aggressive`, `cautious`, `creative` plus domain genes like `testing`, `security`) are combined into timelines that compete. Fitness decides, and FLUX picks the winner itself after at most three generations. Risky genes need safety genes. The graveyard remembers *in which context* something died, so the same gene can be lethal for security code and excellent for prototypes.

**Try:** `/explore "..."` with your module. Look at which context FLUX detects and which timelines it forks. Run `/evolve` a couple of generations, then `/select`. Read what ended up in the graveyard and why.

**Commands:** `/explore`, `/evolve`, `/status`, `/cross`, `/select`, `/terminate`, `/resurrect`.

## 4 · Spore: colonies that share lessons (reference)

What FLUX learns locally (autopsies, winning genomes, fitness functions) is packaged as "spores" and shared peer to peer through git. No central server. Incoming spores are validated and can be quarantined. Every spore has a traceable origin.

**In this workshop you don't use the lab's git transport.** Spores go through the board instead: `tools/spore.sh` and the skill `spore` (`.claude/skills/spore/SKILL.md`), and they reach every group through the hub. The lab stays here as reference for the ideas the skill borrows: validate before you integrate, attribution, diversity.

## Afterwards

Post a line in `#square`: which lab, which insight.
