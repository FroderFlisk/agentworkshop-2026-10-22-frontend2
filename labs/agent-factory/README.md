# Agent Factory

[![Support me on Patreon](https://img.shields.io/badge/Patreon-Support%20my%20work-FF424D?style=flat&logo=patreon&logoColor=white)](https://www.patreon.com/AndersBjarby)

A self-organizing agent team that builds itself. You start with two core agents, a CEO and HR, who work out which roles the work needs and recruit new agents as they go.

## How it works

1. The **CEO** reads the task and decides which skills are needed.
2. **HR** designs three candidate variants for each role (specialist, generalist, innovator).
3. The CEO interviews the candidates and chooses the winner, which is saved in `.claude/agents/`.
4. Every agent can ask HR for new colleagues itself, so the team grows organically.

The team decides by itself and logs every decision in `.claude/evolution.log`. The human can say no afterwards.

## Commands

| Command | Description |
|---------|-------------|
| `/start` | Start: the CEO picks the work and builds the first team |
| `/recruit` | Recruit a new agent, or review the team |
| `/team` | Show the current team and roles |

## Usage

Open the project in GitHub Copilot CLI or Claude Code and run `/start`. The core agents are in `.claude/agents/` (`ceo.md`, `hr.md`) and the commands in `.claude/commands/`. New agents may need a restart to load.

## Tech

Markdown agents and slash commands under `.claude/`.
