# snowdash.nvim

A developer dashboard for Neovim. Shows your PRs, review requests, CI builds, and a configurable custom data section in a split-pane view.

```
┌──────────────────────────────────────────────────────────────────┐
│ editor                                                           │
├───────────────────────────────┬──────────────────────────────────┤
│  My Pull Requests             │  CI Builds                       │
│  #1234 Fix auth... APPROVED   │  36597  completed PASSED  2h 1m  │
│  #1230 Add cache.. PENDING    │  36581  running          3h 2m   │
│                               │                                  │
│  PRs To Review                │  Custom Section (cached 2h ago)  │
│  #1245 Update API...          │  deploy-1  SUCCEEDED  12d ago    │
│  #1240 Refactor...            │  deploy-2  FAILED     12d ago    │
└───────────────────────────────┴──────────────────────────────────┘
```

## Requirements

- Neovim >= 0.10
- [`gh`](https://cli.github.com/) — GitHub CLI, authenticated

## Installation

### lazy.nvim

```lua
{
  "ankur-sharma/snowdash.nvim",
  lazy = false,
  config = function()
    require("snowdash").setup({
      -- GitHub repo for PR queries (auto-detected from git remote if nil)
      github_repo = "myorg/myrepo",
    })
  end,
}
```

## Keybindings

| Key | Action |
|-----|--------|
| `F2` | Toggle dashboard |
| `F3` | Refresh all data |
| `F4` | Sync custom section data |
| `R` | Refresh (in dashboard buffer) |
| `q` | Close dashboard |
| `Enter` | Open URL under cursor |
| `gx` | Open URL under cursor |

## Configuration

```lua
require("snowdash").setup({
  height = 18,

  -- GitHub repo (auto-detected from git remote if nil)
  github_repo = "myorg/myrepo",

  -- Check names to ignore when computing CI status
  ci_skip_checks = { "Graphite / mergeability_check" },

  -- A specific check to show as a "gate" column in My PRs (nil to disable)
  precommit_check_name = "Precommit-Enforcer",

  my_prs = {
    limit = 10,
    title_width = 45,
  },

  review_prs = {
    limit = 10,
    title_width = 45,
    -- Extra search queries (merged with review-requested:@me)
    extra_searches = {
      "state:open label:my-team -author:@me",
    },
  },

  -- CI builds section (right pane, top)
  ci_builds = {
    enabled = true,
    limit = 10,
    -- Command returning JSON array with: build_number, status, branch, commit,
    -- url, created_ms (epoch ms), completed_ms (epoch ms, 0 if running)
    -- Also accepts: CreatedTsMillis, CompletedTsMillis, BuildNumber, etc.
    fetch_command = "my-ci-tool list --json 2>/dev/null",
    -- Optional: command to get pass/fail per build (%s = build ID)
    -- Should output text containing "Tests: N passed, M failed"
    enrich_command = "my-ci-tool get %s 2>/dev/null",
  },

  -- Custom data section (right pane, bottom) — reads from a JSON cache file
  custom_section = {
    enabled = true,
    title = "My Data",
    cache_file = "~/.cache/snowdash/mydata.json",
    sync_command = "my-sync-script",  -- run by F4
    columns = {
      { key = "NAME",   header = "Name",   width = 14 },
      { key = "STATUS", header = "Status", width = 11 },
      { key = "TIME",   header = "When",   width = 10, relative_time = true },
      { key = "COUNT",  header = "Count",  width = 7 },
    },
    status_key = "STATUS",  -- which column to color-code
  },
})
```

## Sections

### My Pull Requests (left, top)
Shows your open PRs with review status, CI status, and optional gate/enforcer status. Data from `gh pr list --author @me`.

### PRs To Review (left, bottom)
Shows PRs where you're requested as a reviewer. Add `extra_searches` to include PRs matching other criteria (e.g. team labels).

### CI Builds (right, top)
Shows recent CI builds. Requires `ci_builds.fetch_command` to be configured. The command should return a JSON array. Pass/fail detail is lazily loaded via `enrich_command` if provided.

### Custom Section (right, bottom)
Displays data from a JSON cache file with configurable columns. Use `sync_command` to define how to refresh the cache. Press `F4` to trigger a sync.

## Color coding

| Color | Statuses |
|-------|----------|
| Green | approved, pass, succeeded, completed, passed |
| Yellow | pending, running, queued, missing, no_review |
| Red | everything else (failed, changes_req, error) |
