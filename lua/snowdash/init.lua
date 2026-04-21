local config = require("snowdash.config")

local M = {}

local state = {
  left_buf = nil,
  right_buf = nil,
  left_win = nil,
  right_win = nil,
  data = {},
  loading = false,
  job_ids = {},
  left_url_map = {},
  right_url_map = {},
  custom_syncing = false,
}

local augroup = vim.api.nvim_create_augroup("Snowdash", { clear = true })
local closing = false

local function setup_highlights()
  local links = {
    SnowdashHeader = "Title",
    SnowdashGreen = "DiagnosticOk",
    SnowdashYellow = "DiagnosticWarn",
    SnowdashRed = "DiagnosticError",
    SnowdashMuted = "Comment",
    SnowdashSeparator = "NonText",
    SnowdashColumnHeader = "Underlined",
  }
  for name, target in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

local function set_buf_options(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "snowdash"
end

local function set_win_options(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winfixheight = true
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].spell = false
  vim.wo[win].list = false
end

local function set_buf_keymaps(buf)
  vim.keymap.set("n", "R", function() M.refresh() end, { buffer = buf, desc = "Refresh Snowdash" })
  vim.keymap.set("n", "q", function() M.toggle() end, { buffer = buf, desc = "Close Snowdash" })
  vim.keymap.set("n", "<CR>", function() M.open_url_under_cursor() end, { buffer = buf, desc = "Open URL" })
  vim.keymap.set("n", "gx", function() M.open_url_under_cursor() end, { buffer = buf, desc = "Open URL" })
end

local function create_buffer(existing_buf)
  if existing_buf and vim.api.nvim_buf_is_valid(existing_buf) then
    return existing_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  set_buf_options(buf)
  set_buf_keymaps(buf)
  return buf
end

local function is_open()
  return state.left_win and vim.api.nvim_win_is_valid(state.left_win)
end

function M.setup(opts)
  config.setup(opts)
  M._setup_done = true
  setup_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = setup_highlights,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(args)
      if closing then return end
      local closed = tonumber(args.match)
      if closed == state.left_win or closed == state.right_win then
        closing = true
        vim.schedule(function()
          local other = (closed == state.left_win) and state.right_win or state.left_win
          if other and vim.api.nvim_win_is_valid(other) then
            pcall(vim.api.nvim_win_close, other, true)
          end
          state.left_win = nil
          state.right_win = nil
          closing = false
        end)
      end
    end,
  })
end

function M.toggle()
  if is_open() then
    closing = true
    if state.right_win and vim.api.nvim_win_is_valid(state.right_win) then
      pcall(vim.api.nvim_win_close, state.right_win, true)
    end
    if state.left_win and vim.api.nvim_win_is_valid(state.left_win) then
      pcall(vim.api.nvim_win_close, state.left_win, true)
    end
    state.left_win = nil
    state.right_win = nil
    closing = false
    return
  end

  state.left_buf = create_buffer(state.left_buf)
  state.right_buf = create_buffer(state.right_buf)

  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd("botright " .. config.options.height .. "split")
  vim.api.nvim_win_set_buf(0, state.left_buf)
  state.left_win = vim.api.nvim_get_current_win()
  set_win_options(state.left_win)

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, state.right_buf)
  state.right_win = vim.api.nvim_get_current_win()
  set_win_options(state.right_win)

  vim.api.nvim_set_current_win(prev_win)

  if not next(state.data) then
    M.refresh()
  end
end

function M.refresh()
  for _, id in ipairs(state.job_ids) do
    pcall(vim.fn.jobstop, id)
  end
  state.job_ids = {}
  state.loading = true
  state.data = {}
  M.render()

  local fetch = require("snowdash.fetch")
  state.job_ids = fetch.fetch_all(function(name, section_data)
    vim.schedule(function()
      state.data[name] = section_data
      state.data._refreshed_at = os.date("%H:%M:%S")
      state.loading = false
      M.render()

      if name == "ci_builds" and section_data.items then
        local enrich_ids = fetch.enrich_build_results(section_data.items, function()
          M.render()
        end)
        for _, id in ipairs(enrich_ids) do
          table.insert(state.job_ids, id)
        end
      end
    end)
  end)
end

function M.render()
  local render = require("snowdash.render")

  if state.left_buf and vim.api.nvim_buf_is_valid(state.left_buf) then
    state.left_url_map = render.render_left(state.left_buf, state.data, state.loading)
  end
  if state.right_buf and vim.api.nvim_buf_is_valid(state.right_buf) then
    state.right_url_map = render.render_right(state.right_buf, state.data, state.loading, state.custom_syncing)
  end
end

function M.open_url_under_cursor()
  local cur_win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(cur_win)[1]

  local url_map
  if cur_win == state.left_win then
    url_map = state.left_url_map
  elseif cur_win == state.right_win then
    url_map = state.right_url_map
  else
    return
  end

  local url = url_map and url_map[line]
  if url then
    vim.ui.open(url)
  end
end

function M.sync_custom()
  local cfg = config.options.custom_section
  if not cfg.enabled or not cfg.sync_command then
    vim.notify("No sync command configured", vim.log.levels.WARN)
    return
  end

  state.custom_syncing = true
  M.render()

  local cache_file = vim.fn.expand(cfg.cache_file)
  local start_mtime = 0
  local stat = vim.uv.fs_stat(cache_file)
  if stat then start_mtime = stat.mtime.sec end

  vim.fn.jobstart({ "sh", "-c", cfg.sync_command }, {
    on_exit = function(_, code)
      vim.schedule(function()
        state.custom_syncing = false
        local new_stat = vim.uv.fs_stat(cache_file)
        local updated = new_stat and new_stat.mtime.sec > start_mtime

        if code == 0 or updated then
          local fetch = require("snowdash.fetch")
          fetch.fetch_custom_section(function(data)
            state.data.custom_section = data
            state.data._refreshed_at = os.date("%H:%M:%S")
            M.render()
          end)
        else
          vim.notify("Sync failed (exit " .. code .. ")", vim.log.levels.ERROR)
          M.render()
        end
      end)
    end,
  })
end

function M.is_open()
  return is_open()
end

return M
