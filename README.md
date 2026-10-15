# claude-statusline

Custom status line for Claude Code (Nord colors):

```
Opus | agent-skills • master | 5h 3% (3h 48m) • 7d 3% (3h 8m) | ctx 12% (24k/200k)
```

- Model name
- Current directory and git branch
- 5-hour and 7-day plan usage, with time until each resets
- Context window usage

Usage numbers come from the OAuth usage endpoint. They are fetched in the background and cached in `/tmp/.claude_usage_cache` for 60 seconds, so rendering never waits on the network.

## Requirements

`jq`, `curl`, GNU `date` and `stat`. Requires a Claude subscription login (reads the token from `~/.claude/.credentials.json`).

## Install

```sh
./install.sh
```

Then start a new Claude Code session. The script sets `statusLine` in `~/.claude/settings.json` to point at wherever this repo is cloned, backing up the existing file to `settings.json.bak` first. Safe to re-run.

To do it by hand instead, add:

```json
"statusLine": {
  "type": "command",
  "command": "sh /path/to/claude-statusline/statusline.sh"
}
```
