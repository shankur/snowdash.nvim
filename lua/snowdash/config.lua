local M = {}

local defaults = {
  height = 18,

  -- GitHub repo for PR queries (owner/repo format)
  github_repo = nil, -- e.g. "myorg/myrepo", auto-detected from git remote if nil

  -- Checks to skip when deriving CI status
  ci_skip_checks = { "Graphite / mergeability_check" },

  -- Check name used to determine precommit/gate status (nil to disable column)
  precommit_check_name = nil, -- e.g. "Precommit-Enforcer"

  my_prs = {
    limit = 10,
    title_width = 45,
  },

  review_prs = {
    limit = 10,
    title_width = 45,
    -- Additional search queries to include (merged with review-requested)
    extra_searches = {}, -- e.g. { "state:open label:my-team -author:@me" }
  },

  ci_builds = {
    enabled = false,
    limit = 10,
    -- Shell command that returns JSON array of builds. Each object should have:
    --   build_number, status, branch, commit (hash), url (optional),
    --   created_ms (epoch ms), completed_ms (epoch ms, 0 if running)
    fetch_command = nil,
    -- Shell command to get pass/fail detail for a single build.
    -- %s is replaced with the build ID. Should output text containing "Tests: N passed, M failed"
    enrich_command = nil, -- e.g. "sf ci build get %s 2>/dev/null"
  },

  custom_section = {
    enabled = false,
    title = "Custom",
    -- Path to a JSON cache file. The plugin reads this file directly.
    cache_file = nil, -- e.g. "~/.cache/snowdash/custom.json"
    -- Shell command or script to refresh the cache (run via F4 / sync)
    sync_command = nil,
    -- Column definitions for the custom section.
    -- Each entry: { key = "json_key", header = "Col", width = 14 }
    columns = {},
    -- Key in each JSON row to use for status color highlighting
    status_key = nil, -- e.g. "STATUS"
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  -- Auto-detect github_repo from git remote if not set
  if not M.options.github_repo then
    local handle = io.popen("git remote get-url origin 2>/dev/null")
    if handle then
      local url = handle:read("*a"):gsub("%s+$", "")
      handle:close()
      local repo = url:match("github%.com[:/](.+)%.git$") or url:match("github%.com[:/](.+)$")
      if repo then
        M.options.github_repo = repo
      end
    end
  end
end

return M
