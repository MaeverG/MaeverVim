-- Vendored from https://github.com/yt20chill/inline_git_blame.nvim, with fixes:
--  * no blocking io.popen calls (git rev-parse / check-ignore) on every CursorHold
--  * git runs from the file's own directory instead of cwd (works across repos / cwd outside repo)
--  * untracked, ignored and non-repo files simply show nothing instead of "Uncommitted changes"
--  * single `git blame --porcelain` call (commit summary included) instead of a second `git show`
--  * stale async results are dropped if the cursor/buffer moved on
--  * autocmds live in an augroup, setup is idempotent, and the module works without setup()
local M = {}

local defaults = {
  debounce_ms = 150,
  excluded_filetypes = { "NvimTree", "neo-tree", "TelescopePrompt", "help" },
  autocmd = true,
  you_label = "You", -- or false to disable replacement
}

M.options = vim.deepcopy(defaults)

local ns = vim.api.nvim_create_namespace("inline_blame")
local group = vim.api.nvim_create_augroup("InlineGitBlame", { clear = true })
local timer = vim.uv.new_timer()
local user_cache = {} -- git root -> user.name

function M.setup(opts)
  opts = opts or {}
  local excluded = vim.deepcopy(defaults.excluded_filetypes)
  vim.list_extend(excluded, vim.tbl_filter(function(ft)
    return type(ft) == "string"
  end, opts.excluded_filetypes or {}))

  M.options = vim.tbl_extend("force", defaults, opts)
  M.options.excluded_filetypes = excluded

  vim.api.nvim_clear_autocmds({ group = group })
  timer:stop()
  if not M.options.autocmd then
    return
  end

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    desc = "Show inline git blame for current line (debounced)",
    callback = function()
      timer:stop()
      timer:start(
        math.max(M.options.debounce_ms, 0),
        0,
        vim.schedule_wrap(function()
          M.inline_blame_current_line()
        end)
      )
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
    group = group,
    desc = "Clear inline git blame on cursor move",
    callback = function()
      timer:stop()
      M.clear_blame()
    end,
  })
end

function M.clear_blame()
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

local function relative_time(author_time)
  local blame_time = tonumber(author_time)
  if not blame_time then
    return "unknown"
  end
  local diff = os.difftime(os.time(), blame_time)
  local function plural(n, unit)
    return string.format("%d %s%s ago", n, unit, n == 1 and "" or "s")
  end
  if diff < 60 then
    return plural(math.max(math.floor(diff), 0), "second")
  elseif diff < 3600 then
    return plural(math.floor(diff / 60), "minute")
  elseif diff < 86400 then
    return plural(math.floor(diff / 3600), "hour")
  elseif diff < 172800 then
    return "yesterday"
  elseif diff < 2592000 then
    return plural(math.floor(diff / 86400), "day")
  elseif diff < 31536000 then
    return plural(math.floor(diff / 2592000), "month")
  end
  return plural(math.floor(diff / 31536000), "year")
end

local function is_blamable(bufnr)
  if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
    return false
  end
  return not vim.tbl_contains(M.options.excluded_filetypes, vim.bo[bufnr].filetype)
end

local function show_blame(bufnr, line, text)
  -- Drop results that arrive after the cursor/buffer moved on
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_get_current_buf() ~= bufnr then
    return
  end
  if vim.api.nvim_win_get_cursor(0)[1] ~= line or line > vim.api.nvim_buf_line_count(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
    virt_text = { { "  " .. text, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

local function with_git_user(cwd, cb)
  if user_cache[cwd] ~= nil then
    return cb(user_cache[cwd])
  end
  vim.system({ "git", "config", "user.name" }, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      user_cache[cwd] = vim.trim(res.stdout or "")
      cb(user_cache[cwd])
    end)
  end)
end

local function parse_porcelain(stdout)
  local sha = stdout:match("^(%x+) ")
  local info = { sha = sha }
  for l in vim.gsplit(stdout, "\n", { plain = true }) do
    if l:find("^\t") then
      break -- file content line, end of header
    end
    info.author = info.author or l:match("^author (.*)")
    info.author_time = info.author_time or l:match("^author%-time (%d+)")
    info.summary = info.summary or l:match("^summary (.*)")
  end
  return info
end

function M.inline_blame_current_line()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_blamable(bufnr) then
    return false
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  M.clear_blame()

  if vim.bo[bufnr].modified then
    show_blame(bufnr, line, "You • Unsaved changes")
    return true
  end

  local file = vim.api.nvim_buf_get_name(bufnr)
  local dir = vim.fs.dirname(file)
  local cmd = { "git", "blame", "--porcelain", "-L", line .. "," .. line, "--", vim.fs.basename(file) }
  if vim.fn.isdirectory(dir) == 0 then
    return false -- e.g. a new file whose directory doesn't exist yet
  end
  vim.system(cmd, { cwd = dir, text = true }, function(res)
    -- Non-zero: not a repo, untracked, ignored, or line out of range. Show nothing.
    if res.code ~= 0 or not res.stdout or res.stdout == "" then
      return
    end
    vim.schedule(function()
      local info = parse_porcelain(res.stdout)
      if not info.sha then
        return
      end
      if info.sha:match("^0+$") then
        return show_blame(bufnr, line, "You • Uncommitted changes")
      end
      with_git_user(dir, function(user)
        local author = info.author or "unknown"
        if M.options.you_label and author == user then
          author = M.options.you_label
        end
        local text = string.format("%s, %s • %s", author, relative_time(info.author_time), info.summary or "")
        show_blame(bufnr, line, text)
      end)
    end)
  end)
  return true
end

function M.toggle_blame_current_line()
  local bufnr = vim.api.nvim_get_current_buf()
  local line0 = vim.api.nvim_win_get_cursor(0)[1] - 1
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { line0, 0 }, { line0, -1 }, {})
  if #marks > 0 then
    M.clear_blame()
  else
    M.inline_blame_current_line()
  end
end

M._test_relative_time = relative_time
return M
