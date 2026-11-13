-- Extra asciidoc rendering for things markview doesn't handle:
-- superscript/subscript, definition lists and tables.
---@class util.adoc
local M = {}

local ns = vim.api.nvim_create_namespace("adoc_extras")
M.cursor_cell = {} ---@type table<integer, string?> text of the table cell under the cursor
M.cursor_grid = {} ---@type table<integer, { index: integer, ncols: integer, pos: integer[][] }?>
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
  vim.api.nvim_set_hl(0, "AdocTableCode", { link = "MarkviewInlineCode", default = true })
  vim.api.nvim_set_hl(0, "AdocTableSel", { link = "Visual", default = true })
  vim.api.nvim_set_hl(0, "AdocTocSel", { link = "CursorLine", default = true })
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

--- Split a cell into { text, is_code } segments (backtick spans become code).
local function segments(text)
  local segs, init = {}, 1
  while true do
    local s, e, inner = text:find("`([^`]+)`", init)
    if not s then
      break
    end
    if s > init then
      segs[#segs + 1] = { text:sub(init, s - 1), false }
    end
    segs[#segs + 1] = { inner, true }
    init = e + 1
  end
  if init <= #text then
    segs[#segs + 1] = { text:sub(init), false }
  end
  return segs
end

local function plain(text)
  return table.concat(vim.tbl_map(function(sg)
    return sg[1]
  end, segments(text)))
end

--- Render rows (list of list of strings) as box-drawing virtual lines.
local function render_table(rows, header, active)
  local ncols = 0
  for _, r in ipairs(rows) do
    ncols = math.max(ncols, #r)
  end
  local widths = {}
  for c = 1, ncols do
    widths[c] = 1
    for _, r in ipairs(rows) do
      widths[c] = math.max(widths[c], vim.fn.strdisplaywidth(plain(r[c] or "")))
    end
  end

  local function rule(l, m, r)
    local parts = {}
    for c = 1, ncols do
      parts[c] = string.rep("─", widths[c] + 2)
    end
    return { { l .. table.concat(parts, m) .. r, "AdocTableBorder" } }
  end

  local function row(r, hl, ri)
    local chunks = { { "│", "AdocTableBorder" } }
    for c = 1, ncols do
      local cell = r[c] or ""
      local h = (active and active[1] == ri and active[2] == c) and "AdocTableSel" or hl
      chunks[#chunks + 1] = { " ", h }
      for _, sg in ipairs(segments(cell)) do
        chunks[#chunks + 1] = { sg[1], (sg[2] and h == hl) and "AdocTableCode" or h }
      end
      chunks[#chunks + 1] = { string.rep(" ", widths[c] - vim.fn.strdisplaywidth(plain(cell))) .. " ", h }
      chunks[#chunks + 1] = { "│", "AdocTableBorder" }
    end
    return chunks
  end

  local lines = { rule("┌", "┬", "┐") }
  for i, r in ipairs(rows) do
    lines[#lines + 1] = row(r, (header and i == 1) and "AdocTableHeader" or "AdocTableCell", i)
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
  local attr = s > 0 and lines[s] or nil -- line above the delimiter (1-based index s)
  local attr_row = (attr and attr:match("^%[.*%]$")) and s - 1 or nil
  if not attr_row then
    attr = nil
  end
  local cells, first_cells, first_blank = {}, nil, false
  local cursor_cell ---@type integer? index into cells under the cursor
  local cell_pos = {} ---@type integer[][] source { row, col } of each cell's `|`
  local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
  for i = s + 1, e - 1 do
    local l = lines[i + 1]
    if l:match("^%s*|") then
      local c = split_cells(l)
      if i == cursor_row then
        -- pick the cell whose `|` is the last one at or before the cursor
        local pick, n = 1, 0
        for pos in l:gmatch("()|") do
          n = n + 1
          if pos - 1 <= cursor_col then
            pick = n
          end
        end
        cursor_cell = #cells + math.min(pick, #c)
      end
      local n = 0
      for pos in l:gmatch("()|") do
        n = n + 1
        if n <= #c then
          cell_pos[#cells + n] = { i + 1, pos - 1 }
        end
      end
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

  local active
  if cursor_cell then
    active = { math.ceil(cursor_cell / ncols), (cursor_cell - 1) % ncols + 1 }
    M.cursor_cell[buf] = plain(cells[cursor_cell])
    M.cursor_grid[buf] = { index = cursor_cell, ncols = ncols, pos = cell_pos, count = #cells }
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
    virt_lines = render_table(rows, header, active),
    virt_lines_above = anchor < 0,
    priority = 200,
  })
end

---------------------------------------------------------------------------
-- Table of contents (`:toc:`): virtual lines with a selectable entry.
-- On the `:toc:` line, j/k move the selection and <CR> jumps to the section.
---------------------------------------------------------------------------

local toc_sel = {} ---@type table<integer, integer>

---@return { row: integer, entries: { row: integer, depth: integer, text: string }[], title: string }?
local function toc_info(buf, lines)
  local toc_row, title, levels
  local entries, fence = {}, nil
  for i, line in ipairs(lines) do
    if fence then
      if line == fence then
        fence = nil
      end
    elseif line:match("^%-%-%-%-+$") or line:match("^%.%.%.%.+$") or line:match("^%+%+%+%++$") then
      fence = line
    elseif line:match("^:toc:") then
      toc_row = toc_row or i - 1
    elseif line:match("^:toc%-title:") then
      title = vim.trim(line:gsub("^:toc%-title:", ""))
    elseif line:match("^:toclevels:") then
      levels = tonumber(vim.trim(line:gsub("^:toclevels:", "")))
    else
      local marker, text = line:match("^(==+)%s+(.-)%s*$")
      if marker and not (i > 1 and lines[i - 1] == "[discrete]") then
        entries[#entries + 1] = { row = i - 1, depth = #marker - 1, text = text }
      end
    end
  end
  if not toc_row then
    return
  end
  entries = vim.tbl_filter(function(e)
    return e.depth <= (levels or 5)
  end, entries)
  return { row = toc_row, entries = entries, title = title ~= "" and title or "Table of contents" }
end

local function render_toc(buf, lines)
  local info = toc_info(buf, lines)
  if not info or #info.entries == 0 then
    return
  end
  local sel = math.min(toc_sel[buf] or 1, #info.entries)
  local on_toc = vim.api.nvim_win_get_cursor(0)[1] - 1 == info.row
  local virt = {}
  for i, e in ipairs(info.entries) do
    local current = on_toc and i == sel
    virt[#virt + 1] = {
      { string.rep("  ", e.depth - 1), current and "AdocTocSel" or "MarkviewPalette5Fg" },
      { e.depth % 2 == 1 and "◆ " or "◇ ", current and "AdocTocSel" or "Comment" },
      { e.text, current and "AdocTocSel" or "MarkviewPalette5Fg" },
    }
  end
  vim.api.nvim_buf_set_extmark(buf, ns, info.row, 0, {
    end_col = #lines[info.row + 1],
    conceal = "",
    virt_text = { { "󰙅 " .. info.title, "MarkviewPalette2Fg" } },
    virt_text_pos = "inline",
    virt_lines = { { { "" } }, unpack(virt) },
    hl_mode = "combine",
    priority = 200,
  })
end

--- j/k/<CR> on the `:toc:` line act on the TOC. Returns "" when handled, nil otherwise.
---@return string?
local function toc_key(buf, key)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local info = enabled() and toc_info(buf, lines) or nil
  if not info or #info.entries == 0 or vim.api.nvim_win_get_cursor(0)[1] - 1 ~= info.row then
    return nil
  end
  local sel = math.min(toc_sel[buf] or 1, #info.entries)
  if key == "<CR>" then
    local target = info.entries[sel]
    vim.schedule(function()
      vim.cmd("normal! m'")
      vim.api.nvim_win_set_cursor(0, { target.row + 1, 0 })
      vim.cmd("normal! zt")
    end)
    return ""
  end
  local step = (key == "j" and 1 or -1) * vim.v.count1
  local new = sel + step
  if new < 1 or new > #info.entries then
    -- leave the TOC: fall through to a normal motion
    return nil
  end
  toc_sel[buf] = new
  vim.schedule(function()
    M.refresh(buf)
  end)
  return ""
end

--- j/k land on visible rows only: lines hidden by markview (conceal_lines) are skipped.
local function hidden(row)
  local ok, h = pcall(vim.api.nvim_win_text_height, 0, { start_row = row, end_row = row })
  return ok and h.all == 0
end

---@return integer number of buffer lines to move so `count` visible rows are crossed
local function vertical_distance(buf, key, count)
  if key ~= "j" and key ~= "k" or not enabled() then
    return count
  end
  local dir = key == "j" and 1 or -1
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
  local row, moved, crossed = cur, 0, 0
  while crossed < count do
    local nxt = row + dir
    if nxt < 0 or nxt > last then
      break
    end
    row, moved = nxt, moved + 1
    if not hidden(row) then
      crossed = crossed + 1
    end
  end
  -- never end on a hidden row (e.g. a hidden line at the very end)
  while moved > 0 and hidden(cur + dir * moved) do
    moved = moved - 1
  end
  return math.max(moved, 1)
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
  M.cursor_cell[buf] = nil
  M.cursor_grid[buf] = nil
  if buf ~= vim.api.nvim_get_current_buf() or not vim.fn.mode():match("^n") or not enabled() then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
  render_toc(buf, lines)
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
  for _, key in ipairs({ "j", "k", "<CR>" }) do
    vim.keymap.set("n", key, function()
      return toc_key(buf, key) or ((vim.v.count > 0 and vim.v.count or "") .. key)
    end, { buffer = buf, expr = true, desc = "Asciidoc TOC navigation" })
  end
  -- keep the rendered table (and its concealed source lines) visible under the cursor in normal mode
  local function conceal_cursor()
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.wo[win].concealcursor = "n"
    end
  end
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter" }, { group = group, buffer = buf, callback = conceal_cursor })
  conceal_cursor()

  -- h/j/k/l move between table cells (only while the cursor is in a rendered table)
  for _, key in ipairs({ "h", "j", "k", "l" }) do
    vim.keymap.set("n", key, function()
      if (key == "j" or key == "k") and toc_key(buf, key) then
        return
      end
      local g = enabled() and M.cursor_grid[buf] or nil
      if g then
        local step = ({ h = -1, l = 1, k = -g.ncols, j = g.ncols })[key] * vim.v.count1
        local col = (g.index - 1) % g.ncols + 1
        local target = g.index + step
        local horizontal = key == "h" or key == "l"
        if horizontal then
          local c = math.max(1, math.min(g.ncols, col + step))
          target = math.min(g.index - col + c, g.count)
        end
        if target >= 1 and target <= g.count and g.pos[target] then
          vim.api.nvim_win_set_cursor(0, g.pos[target])
          return
        elseif horizontal then
          return
        end
      end
      vim.cmd(("normal! %d%s"):format(vertical_distance(buf, key, vim.v.count1), key))
    end, { buffer = buf, desc = "Table cell / cursor motion" })
  end

  -- yy on a table cell yanks just that cell
  vim.keymap.set("n", "yy", function()
    local text = M.cursor_cell[buf]
    local reg = vim.v.register
    if text and enabled() then
      vim.fn.setreg(reg, text)
      vim.notify("Yanked cell: " .. text)
    else
      vim.cmd(('normal! "%s%dyy'):format(reg, vim.v.count1))
    end
  end, { buffer = buf, desc = "Yank table cell / line" })
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
