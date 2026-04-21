local config = require("snowdash.config")

local M = {}

local ns = vim.api.nvim_create_namespace("snowdash")

local function truncate(str, max_len)
  if #str <= max_len then return str end
  return str:sub(1, max_len - 1) .. "…"
end

local function relative_time(iso)
  if not iso or iso == "" then return "" end
  local y, m, d, h, min, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return iso end
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d),
                       hour = tonumber(h), min = tonumber(min), sec = tonumber(s) })
  local utc_offset = os.time(os.date("!*t")) - os.time(os.date("*t"))
  t = t - utc_offset
  local delta = os.time() - t
  if delta < 60 then return "just now" end
  if delta < 3600 then return math.floor(delta / 60) .. "m ago" end
  if delta < 86400 then return math.floor(delta / 3600) .. "h ago" end
  return math.floor(delta / 86400) .. "d ago"
end

local function status_hl(status)
  local s = (status or ""):upper()
  if s == "APPROVED" or s == "PASS" or s == "SUCCEEDED" or s == "COMPLETED" or s == "PASSED" then
    return "SnowdashGreen"
  elseif s == "PENDING" or s == "MISSING" or s == "NO_REVIEW" or s == "RUNNING"
      or s == "QUEUED" or s == "BUILDING" or s == "EXECUTING" then
    return "SnowdashYellow"
  else
    return "SnowdashRed"
  end
end

local function new_ctx()
  return { lines = {}, hls = {}, url_map = {} }
end

local function add_hl(ctx, col_start, col_end, group)
  table.insert(ctx.hls, { line = #ctx.lines - 1, col_start = col_start, col_end = col_end, group = group })
end

local function flush(bufnr, ctx)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, ctx.lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for _, hl in ipairs(ctx.hls) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, hl.line, hl.col_start, {
      end_col = hl.col_end ~= -1 and hl.col_end or nil,
      end_row = hl.col_end == -1 and hl.line + 1 or nil,
      hl_group = hl.group,
    })
  end

  vim.bo[bufnr].modifiable = false
  return ctx.url_map
end

-- Section renderers

local function render_my_prs(ctx, data)
  local section = data.my_prs
  local header = " My Pull Requests"
  table.insert(ctx.lines, header)
  add_hl(ctx, 0, #header, "SnowdashHeader")

  if section and section.error then
    table.insert(ctx.lines, "  Error: " .. section.error)
    add_hl(ctx, 0, -1, "SnowdashRed")
    return
  end

  local items = section and section.items or {}
  if #items == 0 then
    table.insert(ctx.lines, "  No open PRs")
    add_hl(ctx, 0, -1, "SnowdashMuted")
    return
  end

  local tw = config.options.my_prs.title_width
  local has_gate = config.options.precommit_check_name ~= nil
  local col_hdr
  if has_gate then
    col_hdr = string.format("  %-7s %-" .. tw .. "s %-12s %-7s %-10s %s", "PR", "Title", "Review", "CI", "Gate", "Updated")
  else
    col_hdr = string.format("  %-7s %-" .. tw .. "s %-12s %-7s %s", "PR", "Title", "Review", "CI", "Updated")
  end
  table.insert(ctx.lines, col_hdr)
  add_hl(ctx, 0, #col_hdr, "SnowdashColumnHeader")

  for _, pr in ipairs(items) do
    local title = truncate(pr.title, tw)
    local line
    if has_gate then
      line = string.format("  #%-6d %-" .. tw .. "s %-12s %-7s %-10s %s",
        pr.number, title, pr.review_status, pr.ci_status, pr.gate_status or "", relative_time(pr.updated_at))
    else
      line = string.format("  #%-6d %-" .. tw .. "s %-12s %-7s %s",
        pr.number, title, pr.review_status, pr.ci_status, relative_time(pr.updated_at))
    end
    table.insert(ctx.lines, line)
    ctx.url_map[#ctx.lines] = pr.url

    local rs = 10 + tw
    add_hl(ctx, rs, rs + 12, status_hl(pr.review_status))
    add_hl(ctx, rs + 13, rs + 20, status_hl(pr.ci_status))
    if has_gate and pr.gate_status then
      add_hl(ctx, rs + 21, rs + 31, status_hl(pr.gate_status))
    end
  end
end

local function render_review_prs(ctx, data)
  local section = data.review_prs
  table.insert(ctx.lines, "")
  local header = " PRs To Review"
  table.insert(ctx.lines, header)
  add_hl(ctx, 0, #header, "SnowdashHeader")

  if section and section.error then
    table.insert(ctx.lines, "  Error: " .. section.error)
    add_hl(ctx, 0, -1, "SnowdashRed")
    return
  end

  local items = section and section.items or {}
  if #items == 0 then
    table.insert(ctx.lines, "  No PRs awaiting your review")
    add_hl(ctx, 0, -1, "SnowdashMuted")
    return
  end

  local tw = config.options.review_prs.title_width
  local col_hdr = string.format("  %-7s %-" .. tw .. "s %-12s %-7s %-18s %s", "PR", "Title", "Review", "CI", "Author", "Created")
  table.insert(ctx.lines, col_hdr)
  add_hl(ctx, 0, #col_hdr, "SnowdashColumnHeader")

  for _, pr in ipairs(items) do
    local title = truncate(pr.title, tw)
    local author = truncate(pr.author, 18)
    local review = pr.review_status or ""
    local ci = pr.ci_status or ""
    local line = string.format("  #%-6d %-" .. tw .. "s %-12s %-7s %-18s %s",
      pr.number, title, review, ci, author, relative_time(pr.created_at))
    table.insert(ctx.lines, line)
    ctx.url_map[#ctx.lines] = pr.url

    local rs = 10 + tw
    add_hl(ctx, rs, rs + 12, status_hl(review))
    add_hl(ctx, rs + 13, rs + 20, status_hl(ci))
  end
end

local function render_ci_builds(ctx, data)
  local cfg = config.options.ci_builds
  if not cfg.enabled then return end

  local section = data.ci_builds
  local header = " CI Builds"
  table.insert(ctx.lines, header)
  add_hl(ctx, 0, #header, "SnowdashHeader")

  if section and section.error then
    table.insert(ctx.lines, "  Error: " .. section.error)
    add_hl(ctx, 0, -1, "SnowdashRed")
    return
  end

  local items = section and section.items or {}
  if #items == 0 then
    table.insert(ctx.lines, "  No CI builds found")
    add_hl(ctx, 0, -1, "SnowdashMuted")
    return
  end

  local col_hdr = string.format("  %-8s %-11s %-10s %-18s %-9s %s",
    "Build#", "Status", "Result", "Duration", "Commit", "Branch")
  table.insert(ctx.lines, col_hdr)
  add_hl(ctx, 0, #col_hdr, "SnowdashColumnHeader")

  for _, build in ipairs(items) do
    local short_commit = (build.commit or ""):sub(1, 7)
    local branch = truncate(build.branch or "", 35)
    local result = build.result or "..."
    if build.status == "running" then result = "" end
    local line = string.format("  %-8s %-11s %-10s %-18s %-9s %s",
      tostring(build.build_number), build.status, result, build.duration,
      short_commit, branch)
    table.insert(ctx.lines, line)
    if build.url and build.url ~= "" then
      ctx.url_map[#ctx.lines] = build.url
    end

    add_hl(ctx, 10, 21, status_hl(build.status))
    if result ~= "" and result ~= "..." then
      add_hl(ctx, 22, 32, status_hl(result))
    elseif result == "..." then
      add_hl(ctx, 22, 32, "SnowdashMuted")
    end
  end
end

local function render_custom_section(ctx, data, syncing)
  local cfg = config.options.custom_section
  if not cfg.enabled then return end

  local section = data.custom_section
  table.insert(ctx.lines, "")
  local cache_age = section and section.cache_age
  local header = " " .. cfg.title
  local suffix
  if syncing then
    suffix = "  [syncing...]"
  elseif cache_age then
    suffix = "  (cached " .. cache_age .. ")"
  else
    suffix = ""
  end
  table.insert(ctx.lines, header .. suffix)
  add_hl(ctx, 0, #header, "SnowdashHeader")
  if syncing then
    add_hl(ctx, #header, #header + #suffix, "SnowdashYellow")
  elseif suffix ~= "" then
    add_hl(ctx, #header, #header + #suffix, "SnowdashMuted")
  end

  if section and section.error then
    table.insert(ctx.lines, "  Error: " .. section.error)
    add_hl(ctx, 0, -1, "SnowdashRed")
    return
  end

  local items = section and section.items or {}
  if #items == 0 then
    table.insert(ctx.lines, "  No data")
    add_hl(ctx, 0, -1, "SnowdashMuted")
    return
  end

  local columns = cfg.columns or {}
  if #columns == 0 then
    table.insert(ctx.lines, "  (no columns configured)")
    add_hl(ctx, 0, -1, "SnowdashMuted")
    return
  end

  -- Build column header
  local fmt_parts = {}
  for _, col in ipairs(columns) do
    table.insert(fmt_parts, string.format("%-" .. (col.width or 14) .. "s", col.header or col.key))
  end
  local col_hdr = "  " .. table.concat(fmt_parts, " ")
  table.insert(ctx.lines, col_hdr)
  add_hl(ctx, 0, #col_hdr, "SnowdashColumnHeader")

  -- Render rows
  local status_key = cfg.status_key
  for _, row in ipairs(items) do
    local parts = {}
    for _, col in ipairs(columns) do
      local val = row[col.key] or row[col.key:upper()] or row[col.key:lower()] or ""
      if type(val) == "number" then
        val = val > 0 and tostring(val) or "-"
      end
      val = tostring(val)
      if col.relative_time then
        val = relative_time(val)
      end
      table.insert(parts, string.format("%-" .. (col.width or 14) .. "s", truncate(val, col.width or 14)))
    end
    local line = "  " .. table.concat(parts, " ")
    table.insert(ctx.lines, line)

    -- Highlight status column
    if status_key then
      local status_val = row[status_key] or row[status_key:upper()] or row[status_key:lower()] or ""
      -- Find status column position
      local offset = 2
      for _, col in ipairs(columns) do
        if col.key == status_key then
          add_hl(ctx, offset, offset + (col.width or 14), status_hl(tostring(status_val)))
          break
        end
        offset = offset + (col.width or 14) + 1
      end
    end
  end
end

local function render_loading(ctx)
  table.insert(ctx.lines, "")
  table.insert(ctx.lines, "  Loading...")
  add_hl(ctx, 0, -1, "SnowdashMuted")
end

function M.render_left(bufnr, data, loading)
  local ctx = new_ctx()
  if loading and not next(data) then
    render_loading(ctx)
  else
    render_my_prs(ctx, data)
    render_review_prs(ctx, data)
  end
  return flush(bufnr, ctx)
end

function M.render_right(bufnr, data, loading, custom_syncing)
  local ctx = new_ctx()
  if loading and not next(data) then
    render_loading(ctx)
  else
    render_ci_builds(ctx, data)
    render_custom_section(ctx, data, custom_syncing)
  end
  return flush(bufnr, ctx)
end

return M
