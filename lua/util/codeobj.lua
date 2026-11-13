-- `ib` text object for markdown/asciidoc: inside the code span or fenced block under the cursor,
-- falling back to the regular `ib` (brackets) elsewhere.
---@class util.codeobj
local M = {}

---@param line string
---@return string? marker
local function fence_marker(line, ft)
  if ft == "asciidoc" then
    return line:match("^(%-%-%-%-+)%s*$") or line:match("^(%.%.%.%.+)%s*$")
  end
  return line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
end

--- 1-based first/last inner rows of the fenced block containing `row`.
local function block_range(lines, row, ft)
  local open, marker
  for i, line in ipairs(lines) do
    local m = fence_marker(line, ft)
    if m then
      if not open then
        open, marker = i, m
      elseif m:sub(1, 1) == marker:sub(1, 1) and #m >= #marker then
        if row >= open and row <= i then
          return open + 1, i - 1
        end
        open = nil
      end
    end
    if i > row and not open then
      return
    end
  end
end

--- 0-based first/last inner columns of the `code` span containing `col`.
local function span_range(line, col)
  local ticks = {}
  for pos in line:gmatch("()`") do
    ticks[#ticks + 1] = pos - 1
  end
  for i = 1, #ticks - 1, 2 do
    if col >= ticks[i] and col <= ticks[i + 1] and ticks[i + 1] - ticks[i] > 1 then
      return ticks[i] + 1, ticks[i + 1] - 1
    end
  end
end

local function select_inner()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local first, last = block_range(lines, row, ft)
  if first and last >= first then
    vim.cmd(("normal! %dGV%dG"):format(first, last))
    return true
  end
  local s, e = span_range(lines[row], col)
  if s then
    vim.api.nvim_win_set_cursor(0, { row, s })
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, { row, e })
    return true
  end
  return false
end

function M.attach(buf)
  for _, mode in ipairs({ "o", "x" }) do
    vim.keymap.set(mode, "ib", function()
      local vis_mode = mode == "x" and vim.fn.mode() or "v"
      if mode == "x" then
        vim.cmd("normal! \27") -- leave visual mode so the selection starts fresh
      end
      if not select_inner() then
        if mode == "x" then
          vim.cmd("normal! gv")
        end
        require("mini.ai").select_textobject("i", "b", { vis_mode = vis_mode })
      end
    end, { buffer = buf, desc = "Inside code span/block (or brackets)" })
  end
end

return M
