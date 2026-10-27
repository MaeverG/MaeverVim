-- macOS kills nvim ("Code Signature Invalid") when it dlopens a treesitter parser
-- that nvim-treesitter just rebuilt in place. Re-create each new/changed parser as a
-- fresh, ad-hoc signed file. Runs at startup (catches parsers changed while nvim was
-- closed) and via a watcher on the parser dir (catches :TSUpdate while nvim is open).
local M = {}

local state_file = vim.fn.stdpath("state") .. "/parser_signed.json"
local parser_dir = vim.fn.stdpath("data") .. "/site/parser"

---@return table<string, number> mtime (seconds) of each parser we've already handled
local function read_state()
  local f = io.open(state_file, "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(data) == "table" and data or {}
end

local function write_state(state)
  local f = io.open(state_file, "w")
  if f then
    f:write(vim.json.encode(state))
    f:close()
  end
end

--- Fix every parser whose mtime differs from what we last handled.
---@param first_run? boolean when there is no state yet, just record what's there
function M.check(first_run)
  local state, had_state = read_state(), vim.uv.fs_stat(state_file) ~= nil
  local changed, failed = false, {}
  for _, name in ipairs(vim.fn.readdir(parser_dir)) do
    if name:match("%.so$") then
      local path = parser_dir .. "/" .. name
      local stat = vim.uv.fs_stat(path)
      if stat and state[name] ~= stat.mtime.sec then
        if had_state or not first_run then
          local tmp = path .. ".new"
          local ok = vim.uv.fs_copyfile(path, tmp)
            and vim.system({ "codesign", "--force", "--sign", "-", tmp }):wait().code == 0
            and vim.uv.fs_rename(tmp, path)
          if not ok then
            vim.uv.fs_unlink(tmp)
            failed[#failed + 1] = name
          end
          stat = vim.uv.fs_stat(path) or stat
        end
        if not vim.tbl_contains(failed, name) then
          state[name] = stat.mtime.sec
        end
        changed = true
      end
    end
  end
  if changed then
    write_state(state)
  end
  if #failed > 0 then
    vim.notify("Could not re-sign treesitter parsers: " .. table.concat(failed, ", "), vim.log.levels.WARN)
  end
end

function M.setup()
  if vim.fn.has("mac") == 0 or vim.fn.isdirectory(parser_dir) == 0 then
    return
  end
  M.check(true)

  local timer = assert(vim.uv.new_timer())
  local watcher = assert(vim.uv.new_fs_event())
  watcher:start(parser_dir, {}, function(_, filename)
    if filename and filename:match("%.so$") then
      -- debounce: an install writes several times and for several parsers
      timer:stop()
      timer:start(
        2000,
        0,
        vim.schedule_wrap(function()
          M.check()
        end)
      )
    end
  end)
end

return M
