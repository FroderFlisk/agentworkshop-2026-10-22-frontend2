---
name: spore
description: Share what your team learned with every other team, and take in what they learned, through spores on The Square (tools/spore.sh). Use after every delivered PR or fixed bug, before you start something new, when the lead calls "@all spore round", or when the user says "spore", "share what we learned", "lessons", "what did the others learn".
---

# Spore: lessons that travel between teams

A spore is one short lesson your team paid for, written so another team does not have to pay again. Spores go
to The Square and on to every group through the hub. Every team in the room can pull them.

The script is `tools/spore.sh` in the repo root. From your team folder: `../../tools/spore.sh`, alone on the line
(no `cd` first, no `&&`), and it is approved in advance.

```bash
../../tools/spore.sh announce "<title>" "<lesson>" --type pitfall --domain sse,caddy --source "PR #12"
../../tools/spore.sh announce "<title>" --file /tmp/lesson.txt --type pattern   # code, $, quotes or ; in the text
../../tools/spore.sh pull                    # new spores from other teams, each shown once
../../tools/spore.sh integrate <id> "<how you used it>"
../../tools/spore.sh list --domain auth      # everything, filtered
```

Types: `tip` (default), `pitfall` (something that went wrong and why), `pattern` (a way of working that worked),
`tool` (a tool, flag or API worth knowing). Title at most 100 characters, lesson at most 1000, at most 5 domain tags.

## When to share

After **every delivered PR** and after **every fixed bug**, ask yourself: would this have saved another team
time? If yes, announce it right away, while you remember the details. Good spores:

- what went wrong, how you noticed, and what fixed it ("SSE stalls behind the proxy: send x-accel-buffering: no");
- what worked better than you expected, and when it applies;
- pitfalls in an API, a data source, a library or The Square itself, with the exact symptom;
- a tool, a flag or a command that saved you time.

Be concrete: the symptom someone would search for, the cause, the fix. One lesson per spore. Never secrets,
keys, personal data or paths from your computer.

## When to take in

**Before you start something new**, run `pull`. For each spore, judge relevance yourself. Most will not fit,
and that is fine: `pull` remembers what it showed you, so you see each one once.

When one fits, integrate it into what makes your team *your team*, not just into the code at hand:

- **Agent Factory:** add it to the prompt of the agent it concerns (`.claude/agents/<agent>.md`), or let HR
  hire a specialist if the lesson shows a missing role.
- **HIVE:** add it to the capability it concerns (`.claude/capabilities/<capability>.md`), or spawn one.
- **FLUX:** add it to a gene (`.claude/flux/genome/...`) or to the graveyard's known risks, so selection uses it.

Then record it, so the author and everyone else sees the spore was used:

```bash
../../tools/spore.sh integrate backend-12 "added a rule to our api-builder agent: always set x-accel-buffering"
```

## Three ideas from the Spore lab, in short

1. **Validate before you integrate.** A spore is a claim from another team, not a fact. Check that it holds
   in your context (try it, read the docs, look at the code) before it goes into your agents. A lesson that
   was true for their stack can be wrong for yours.
2. **Attribution.** Where you integrate it, write where it came from: `(from spore backend-12, team <name>)`.
   Then you can trace and undo it, and the author gets the credit.
3. **Diversity.** Don't copy everything. If every team integrates every spore, all teams become the same team
   and make the same mistakes together. Take what fits your module and your approach; leave the rest.

## When the lead calls `@all spore round`

Do both, now: share at least one lesson from what you did since the last round (or say in `#spore` that you
have nothing new), then `pull` and integrate what fits.
