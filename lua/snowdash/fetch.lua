local config = require("snowdash.config")

local M = {}

local function jobstart_json(cmd, callback)
  local chunks = {}
  return vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(chunks, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          callback(nil, "command exited with code " .. code)
        end)
        return
      end
      local raw = table.concat(chunks, "\n")
      local ok, decoded = pcall(vim.json.decode, raw)
      vim.schedule(function()
        if ok then
          callback(decoded, nil)
        else
          callback(nil, "JSON parse error")
        end
      end)
    end,
  })
end

local function jobstart_lines(cmd, callback)
  local chunks = {}
  return vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          table.insert(chunks, line)
        end
      end
    end,
    on_exit = function(_, code)
      while #chunks > 0 and chunks[#chunks] == "" do
        table.remove(chunks)
      end
      vim.schedule(function()
        if code ~= 0 then
          callback(nil, "command exited with code " .. code)
        else
          callback(chunks, nil)
        end
      end)
    end,
  })
end

-- Derive review status from gh PR JSON
local function derive_review_status(pr)
  local rd = pr.reviewDecision or ""
  if rd == "APPROVED" then return "APPROVED"
  elseif rd == "CHANGES_REQUESTED" then return "CHANGES_REQ"
  elseif rd == "REVIEW_REQUIRED" then return "PENDING"
  else return "NO_REVIEW"
  end
end

-- Derive CI status from statusCheckRollup
local function derive_ci_status(pr)
  local checks = pr.statusCheckRollup or {}
  local skip = {}
  for _, name in ipairs(config.options.ci_skip_checks or {}) do
    skip[name] = true
  end

  local has_failure = false
  local has_pending = false

  for _, check in ipairs(checks) do
    local name = check.name or ""
    local conclusion = check.conclusion or ""
    local status = check.status or ""
    local state_val = check.state or ""

    if skip[name] or conclusion == "SKIPPED" then
      goto continue
    end

    if check.__typename == "StatusContext" then
      if state_val == "FAILURE" or state_val == "ERROR" then has_failure = true
      elseif state_val == "PENDING" then has_pending = true
      end
    else
      if conclusion == "FAILURE" then has_failure = true
      elseif status == "IN_PROGRESS" or (status == "COMPLETED" and conclusion == "") then has_pending = true
      end
    end

    ::continue::
  end

  if has_failure then return "FAIL" end
  if has_pending then return "PENDING" end
  return "PASS"
end

-- Check a specific gate/enforcer status from statusCheckRollup
local function derive_gate_status(pr)
  local gate_name = config.options.precommit_check_name
  if not gate_name then return nil end

  local checks = pr.statusCheckRollup or {}
  local found = false
  local passed = false

  for _, check in ipairs(checks) do
    if (check.name or "") == gate_name then
      found = true
      if check.conclusion == "SUCCESS" then passed = true end
    end
  end

  if not found then return "MISSING" end
  if passed then return "PASS" end
  return "FAIL"
end

function M.fetch_my_prs(callback)
  local cfg = config.options.my_prs
  local repo = config.options.github_repo
  if not repo then
    callback({ error = "github_repo not configured" })
    return nil
  end

  local cmd = {
    "gh", "pr", "list",
    "--repo", repo,
    "--author", "@me",
    "--json", "number,title,reviewDecision,statusCheckRollup,url,updatedAt",
    "--limit", tostring(cfg.limit),
  }
  return jobstart_json(cmd, function(data, err)
    if err then
      callback({ error = err })
      return
    end
    local items = {}
    for _, pr in ipairs(data or {}) do
      table.insert(items, {
        number = pr.number,
        title = pr.title or "",
        review_status = derive_review_status(pr),
        ci_status = derive_ci_status(pr),
        gate_status = derive_gate_status(pr),
        url = pr.url or "",
        updated_at = pr.updatedAt or "",
      })
    end
    callback({ items = items })
  end)
end

function M.fetch_review_prs(callback)
  local cfg = config.options.review_prs
  local repo = config.options.github_repo
  if not repo then
    callback({ error = "github_repo not configured" })
    return nil
  end

  local json_fields = "number,title,author,createdAt,url,reviewDecision,statusCheckRollup"

  local extra = cfg.extra_searches or {}
  local total_searches = 1 + #extra
  local results = {}
  local pending = total_searches

  local function merge_and_callback()
    pending = pending - 1
    if pending > 0 then return end

    local seen = {}
    local items = {}
    for _, pr in ipairs(results) do
      if not seen[pr.number] then
        seen[pr.number] = true
        table.insert(items, pr)
      end
    end
    callback({ items = items })
  end

  local function parse_prs(data)
    local parsed = {}
    for _, pr in ipairs(data or {}) do
      local author = ""
      if pr.author then
        author = pr.author.name or pr.author.login or ""
      end
      table.insert(parsed, {
        number = pr.number,
        title = pr.title or "",
        author = author,
        review_status = derive_review_status(pr),
        ci_status = derive_ci_status(pr),
        created_at = pr.createdAt or "",
        url = pr.url or "",
      })
    end
    return parsed
  end

  local function do_search(search_query)
    local cmd = {
      "gh", "pr", "list",
      "--repo", repo,
      "--search", search_query,
      "--json", json_fields,
      "--limit", tostring(cfg.limit),
    }
    return jobstart_json(cmd, function(data, err)
      if not err then
        for _, item in ipairs(parse_prs(data)) do
          table.insert(results, item)
        end
      end
      merge_and_callback()
    end)
  end

  local job_ids = {}

  local id = do_search("state:open review-requested:@me")
  if id then table.insert(job_ids, id) end

  for _, search in ipairs(extra) do
    id = do_search(search)
    if id then table.insert(job_ids, id) end
  end

  return job_ids
end

function M.fetch_ci_builds(callback)
  local cfg = config.options.ci_builds
  if not cfg.enabled or not cfg.fetch_command then
    callback({ items = {} })
    return nil
  end

  local cmd = { "sh", "-c", cfg.fetch_command }
  return jobstart_json(cmd, function(decoded, err)
    if err then
      callback({ error = err })
      return
    end
    if type(decoded) ~= "table" then
      callback({ error = "unexpected CI build output" })
      return
    end

    local items = {}
    for _, build in ipairs(decoded) do
      local created_ms = tonumber(build.created_ms or build.CreatedTsMillis) or 0
      local completed_ms = tonumber(build.completed_ms or build.CompletedTsMillis) or 0
      local duration = ""
      if completed_ms > 0 and created_ms > 0 then
        local secs = math.floor((completed_ms - created_ms) / 1000)
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        duration = string.format("%dh %dm", h, m)
      elseif created_ms > 0 then
        local secs = math.floor((os.time() * 1000 - created_ms) / 1000)
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        duration = string.format("%dh %dm (running)", h, m)
      end

      local created_iso = ""
      if created_ms > 0 then
        created_iso = os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(created_ms / 1000))
      end

      table.insert(items, {
        id = build.id or build.ID or "",
        build_number = build.build_number or build.BuildNumber or 0,
        status = build.status or build.Status or "",
        branch = build.branch or build.Branch or "",
        commit = build.commit or build.GitHash or "",
        duration = duration,
        created_at = created_iso,
        url = build.url or "",
      })
    end

    callback({ items = items })
  end)
end

-- Enrich completed builds with pass/fail detail
function M.enrich_build_results(items, on_update)
  local enrich_cmd = config.options.ci_builds.enrich_command
  if not enrich_cmd then return {} end

  local job_ids = {}
  for _, build in ipairs(items) do
    if build.status == "completed" and build.id ~= "" then
      local cmd = { "sh", "-c", enrich_cmd:format(build.id) }
      local id = jobstart_lines(cmd, function(lines, err)
        if err or not lines then return end
        for _, line in ipairs(lines) do
          local p, f = line:match("Tests:%s+(%d+) passed,%s+(%d+) failed")
          if p then
            build.test_passed = tonumber(p)
            build.test_failed = tonumber(f)
            build.result = tonumber(f) > 0 and "FAILED" or "PASSED"
            vim.schedule(on_update)
            break
          end
        end
      end)
      if id then table.insert(job_ids, id) end
    end
  end
  return job_ids
end

function M.fetch_custom_section(callback)
  local cfg = config.options.custom_section
  if not cfg.enabled or not cfg.cache_file then
    callback({ items = {} })
    return nil
  end

  local cache_file = vim.fn.expand(cfg.cache_file)
  local f = io.open(cache_file, "r")
  if not f then
    callback({ error = "No cache file. Run sync command." })
    return nil
  end

  local raw = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    callback({ error = "Cache file corrupt" })
    return nil
  end

  local stat = vim.uv.fs_stat(cache_file)
  local age = ""
  if stat then
    local delta = os.time() - stat.mtime.sec
    if delta < 60 then age = "just now"
    elseif delta < 3600 then age = math.floor(delta / 60) .. "m ago"
    elseif delta < 86400 then age = math.floor(delta / 3600) .. "h ago"
    else age = math.floor(delta / 86400) .. "d ago"
    end
  end

  callback({ items = decoded, cache_age = age })
  return nil
end

function M.fetch_all(on_update)
  local job_ids = {}

  local function on_section(name)
    return function(data)
      on_update(name, data)
    end
  end

  local function collect_ids(ret)
    if type(ret) == "table" then
      for _, id in ipairs(ret) do
        table.insert(job_ids, id)
      end
    elseif ret then
      table.insert(job_ids, ret)
    end
  end

  collect_ids(M.fetch_my_prs(on_section("my_prs")))
  collect_ids(M.fetch_review_prs(on_section("review_prs")))
  collect_ids(M.fetch_ci_builds(on_section("ci_builds")))
  collect_ids(M.fetch_custom_section(on_section("custom_section")))

  return job_ids
end

return M
