-- Extra asciidoc rendering for things markview doesn't handle:
-- superscript/subscript, definition lists and tables.
---@class util.adoc
local M = {}

local ns = vim.api.nvim_create_namespace("adoc_extras")
local group = vim.api.nvim_create_augroup("adoc_extras", { clear = true })

local SUP = {
  ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴", ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷",
  ["8"] = "⁸", ["9"] = "⁹", ["+"] = "⁺", ["-"] = "⁻", ["="] = "⁼", ["("] = "⁽", [")"] = "⁾", a = "ᵃ",
  b = "ᵇ", c = "ᶜ", d = "ᵈ", e = "ᵉ", f = "ᶠ", g = "ᵍ", h = "ʰ", i = "ⁱ", j = "ʲ", k = "ᵏ", l = "ˡ",
  m = "ᵐ", n = "ⁿ", o = "ᵒ", p = "ᵖ", r = "ʳ", s = "ˢ", t = "ᵗ", u = "ᵘ", v = "ᵛ", w = "ʷ", x = "ˣ",
  y = "ʸ", z = "ᶻ",
}
local SUB = {
  ["0"] = "₀", ["1"] = "₁", ["2"] = "₂", ["3"] = "₃", ["4"] = "₄", ["5"] = "₅", ["6"] = "₆", ["7"] = "₇",
  ["8"] = "₈", ["9"] = "₉", ["+"] = "₊", ["-"] = "₋", ["="] = "₌", ["("] = "₍", [")"] = "₎", a = "ₐ",
  e = "ₑ", h = "ₕ", i = "ᵢ", j = "ⱼ", k = "ₖ", l = "ₗ", m = "ₘ", n = "ₙ", o = "ₒ", p = "ₚ", r = "ᵣ",
  s = "ₛ", t = "ₜ", u = "ᵤ", v = "ᵥ", x = "ₓ",
}

local function set_highlights()
  vim.api.nvim_set_hl(0, "AdocSup", { link = "@markup.italic", default = true })
  vim.api.nvim_set_hl(0, "AdocSub", { link = "@markup.italic", default = true })
  vim.api.nvim_set_hl(0, "AdocTerm", { link = "@markup.strong", default = true })
  vim.api.nvim_set_hl(0, "AdocTableBorder", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "AdocTableHeader", { link = "@markup.heading", default = true })
  vim.api.nvim_set_hl(0, "AdocTableCell", { link = "Normal", default = true })
end

local function enabled()
  local ok, state = pcall(require, "markview.state")
  return ok and state.enabled()
end

---------------------------------------------------------------------------
-- Super / subscript
---------------------------------------------------------------------------

local function script(buf, row, line, marker, map, hl)
  local init = 1
  while true do
    local s, e, inner = line:find("%" .. marker .. "([^%s%" .. marker .. "]+)%" .. marker, init)
    if not s then
      break
    end
    init = e + 1
    -- hide the markers, keep the text itself (so the cursor can still move through it)
    vim.api.nvim_buf_set_extmark(buf, ns, row, s - 1, { end_col = s, conceal = "", priority = 200 })
    vim.api.nvim_buf_set_extmark(buf, ns, row, e - 1, { end_col = e, conceal = "", priority = 200 })
    vim.api.nvim_buf_set_extmark(buf, ns, row, s, { end_col = e - 1, hl_group = hl, priority = 200 })
    -- overlay each char that has a unicode form (adjacent conceals get merged into one)
    local col = s
    for ch in inner:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      if map[ch] then
        vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
          virt_text = { { map[ch], hl } },
          virt_text_pos = "overlay",
          priority = 200,
        })
      end
      col = col + #ch
    end
  end
end

---------------------------------------------------------------------------
-- Definition lists
---------------------------------------------------------------------------

local function definition(buf, row, line)
  local term, rest = line:match("^(%S.-)::%s+(.*)$")
  if not term then
    term = line:match("^(%S.-)::$")
    rest = ""
  end
  if not term or term:find("^[=*.%-%s|/]") or term:find("[:%[]") then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_col = #term, hl_group = "AdocTerm", priority = 200 })
  vim.api.nvim_buf_set_extmark(buf, ns, row, #term, {
    end_col = #term + 2,
    conceal = "",
    virt_text = { { " ›", "Special" } },
    virt_text_pos = "inline",
    priority = 200,
  })
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------

local function split_cells(line)
  local cells = {}
  for cell in line:gmatch("|([^|]*)") do
    cells[#cells + 1] = vim.trim(cell)
  end
  return cells
end

local function pad(text, width)
  return text .. string.rep(" ", width - vim.fn.strdisplaywidth(text))
end

--- Render rows (list of list of strings) as box-drawing virtual lines.
local function render_table(rows, header)
  local ncols = 0
  for _, r in ipairs(rows) do
    ncols = math.max(ncols, #r)
  end
  local widths = {}
  for c = 1, ncols do
    widths[c] = 1
    for _, r in ipairs(rows) do
      widths[c] = math.max(widths[c], vim.fn.strdisplaywidth(r[c] or ""))
    end
  end

  local function rule(l, m, r)
    local parts = {}
    for c = 1, ncols do
      parts[c] = string.rep("─", widths[c] + 2)
    end
    return { { l .. table.concat(parts, m) .. r, "AdocTableBorder" } }
  end

  local function row(r, hl)
    local chunks = { { "│", "AdocTableBorder" } }
    for c = 1, ncols do
      chunks[#chunks + 1] = { " " .. pad(r[c] or "", widths[c]) .. " ", hl }
      chunks[#chunks + 1] = { "│", "AdocTableBorder" }
    end
    return chunks
  end

  local lines = { rule("┌", "┬", "┐") }
  for i, r in ipairs(rows) do
    lines[#lines + 1] = row(r, (header and i == 1) and "AdocTableHeader" or "AdocTableCell")
    if header and i == 1 and #rows > 1 then
      lines[#lines + 1] = rule("├", "┼", "┤")
    end
  end
  lines[#lines + 1] = rule("└", "┴", "┘")
  return lines
end

local function ncols_from_attr(attr)
  if not attr then
    return nil
  end
  local spec = attr:match('cols%s*=%s*"?([^"%]]+)"?')
  if not spec then
    return nil
  end
  local n = spec:match("^(%d+)%*")
  if n then
    return tonumber(n)
  end
  local count = 0
  for _ in spec:gmatch("[^,]+") do
    count = count + 1
  end
  return count > 0 and count or nil
end

local function table_block(buf, s, e, lines, cursor_row)
  -- s/e are 0-based rows of the `|===` delimiters
  if cursor_row >= s and cursor_row <= e then
    return
  end
  local attr = s > 0 and lines[s] or nil -- line above the delimiter (1-based index s)
  local attr_row = (attr and attr:match("^%[.*%]$")) and s - 1 or nil
  if not attr_row then
    attr = nil
  end
  local cells, first_cells, first_blank = {}, nil, false
  for i = s + 1, e - 1 do
    local l = lines[i + 1]
    if l:match("^%s*|") then
      local c = split_cells(l)
      first_cells = first_cells or #c
      vim.list_extend(cells, c)
    elseif l:match("^%s*$") and first_cells and not first_blank and #cells == first_cells then
      first_blank = true
    end
  end
  if #cells == 0 then
    return
  end
  local ncols = ncols_from_attr(attr) or first_cells or 1
  local header = first_blank or (attr ~= nil and attr:find("header", 1, true) ~= nil)
  local rows = {}
  for i = 1, #cells, ncols do
    rows[#rows + 1] = vim.list_slice(cells, i, math.min(i + ncols - 1, #cells))
  end

  -- virtual lines attached to a concealed line are hidden too, so anchor on the line above
  local first = attr_row or s
  local anchor = first - 1
  for r = first, e do
    if anchor >= 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, r, 0, { conceal_lines = "", priority = 200 })
    else
      vim.api.nvim_buf_set_extmark(buf, ns, r, 0, { end_col = #lines[r + 1], conceal = "", priority = 200 })
    end
  end
  vim.api.nvim_buf_set_extmark(buf, ns, math.max(anchor, 0), 0, {
    virt_lines = render_table(rows, header),
    virt_lines_above = anchor < 0,
    priority = 200,
  })
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

function M.refresh(buf)
  if not buf or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  M.clear(buf)
  if buf ~= vim.api.nvim_get_current_buf() or not vim.fn.mode():match("^n") or not enabled() then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local fence ---@type string?
  local tbl_start ---@type integer?

  for i, line in ipairs(lines) do
    local row = i - 1
    if fence then
      if line == fence then
        fence = nil
      end
    elseif tbl_start then
      if line:match("^|===+%s*$") then
        table_block(buf, tbl_start, row, lines, cursor_row)
        tbl_start = nil
      end
    elseif line:match("^|===+%s*$") then
      tbl_start = row
    elseif line:match("^%-%-%-%-+$") or line:match("^%.%.%.%.+$") or line:match("^%+%+%+%++$") then
      fence = line
    elseif not line:match("^//") then
      script(buf, row, line, "^", SUP, "AdocSup")
      script(buf, row, line, "~", SUB, "AdocSub")
      definition(buf, row, line)
    end
  end
end

function M.attach(buf)
  set_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  vim.api.nvim_create_autocmd(
    { "BufEnter", "BufWinEnter", "TextChanged", "CursorMoved", "CursorHold" },
    { group = group, buffer = buf, callback = function() M.refresh(buf) end }
  )
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    buffer = buf,
    callback = function()
      if vim.v.event.new_mode:match("^n") then
        M.refresh(buf)
      else
        M.clear(buf)
      end
    end,
  })
  M.refresh(buf)
end

--- Toggle markview and the extra rendering together.
function M.toggle()
  vim.cmd("Markview toggle")
  vim.schedule(function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[b].filetype == "asciidoc" then
        M.refresh(b)
      end
    end
  end)
end

return M
