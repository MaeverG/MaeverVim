-- Extra markdown helpers: typography/inline-html rendering, list continuation,
-- heading navigation/outline, word count.
---@class util.markdown
local M = {}

local ns = vim.api.nvim_create_namespace("md_extras")

---------------------------------------------------------------------------
-- Highlights
---------------------------------------------------------------------------

local function set_highlights()
  local function extend(name, attrs)
    local cur = vim.api.nvim_get_hl(0, { name = name, link = false })
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", cur, attrs))
  end
  extend("@markup.strong", { bold = true })
  extend("@markup.italic", { italic = true })
  extend("@markup.strikethrough", { strikethrough = true })
  extend("@markup.underline", { underline = true })
  vim.api.nvim_set_hl(0, "MdBold", { bold = true })
  vim.api.nvim_set_hl(0, "MdItalic", { italic = true })
  vim.api.nvim_set_hl(0, "MdUnderline", { underline = true })
  vim.api.nvim_set_hl(0, "MdStrike", { strikethrough = true })
end

---------------------------------------------------------------------------
-- Treesitter helpers
---------------------------------------------------------------------------

local function rendering()
  local ok, state = pcall(require, "render-markdown.state")
  return ok and state.enabled ~= false
end

---@return TSNode?
local function node_at(buf, row, col)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
  return ok and node or nil
end

local code_queries = {
  markdown = "[(fenced_code_block) (indented_code_block) (minus_metadata) (plus_metadata) (html_block)] @c",
  markdown_inline = "[(code_span) (link_destination) (uri_autolink)] @c",
}

--- Ranges where typography must not be applied: { sr, sc, er, ec } (0-based, end exclusive).
local function excluded_ranges(buf, first, last)
  local ranges = {}
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if not ok or not parser then
    return ranges
  end
  parser:parse(true)
  parser:for_each_tree(function(tree, ltree)
    local src = code_queries[ltree:lang()]
    if not src then
      return
    end
    local qok, query = pcall(vim.treesitter.query.parse, ltree:lang(), src)
    if not qok then
      return
    end
    for _, node in query:iter_captures(tree:root(), buf, first, last + 1) do
      local sr, sc, er, ec = node:range()
      ranges[#ranges + 1] = { sr, sc, er, ec }
    end
  end)
  return ranges
end

local function is_excluded(ranges, row, col)
  for _, r in ipairs(ranges) do
    local after = row > r[1] or (row == r[1] and col >= r[2])
    local before = row < r[3] or (row == r[3] and col < r[4])
    if after and before then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Typography + inline html (applied only while rendered)
---------------------------------------------------------------------------

local html_tags = {
  b = "MdBold",
  strong = "MdBold",
  i = "MdItalic",
  em = "MdItalic",
  u = "MdUnderline",
  ins = "MdUnderline",
  s = "MdStrike",
  del = "MdStrike",
  strike = "MdStrike",
  mark = "RenderMarkdownInlineHighlight",
  kbd = "RenderMarkdownCodeInline",
  code = "RenderMarkdownCodeInline",
}

local function is_rule_or_table_sep(line)
  return line:match("^%s*%-%-%-+%s*$") or (line:find("|", 1, true) and line:match("^[%s|:%-]+$"))
end

local function conceal(buf, row, col, len, char)
  vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
    end_col = col + len,
    conceal = char,
    priority = 200,
  })
end

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
  local mode = vim.fn.mode()
  if buf ~= vim.api.nvim_get_current_buf() or not mode:match("^n") or not rendering() then
    return
  end

  local first = math.max(vim.fn.line("w0") - 1, 0)
  local bottom = vim.fn.line("w$")
  local last = math.min(bottom > 0 and bottom or math.huge, vim.api.nvim_buf_line_count(buf)) - 1
  if last < first then
    return
  end
  local ranges = excluded_ranges(buf, first, last)
  local lines = vim.api.nvim_buf_get_lines(buf, first, last + 1, false)

  for i, line in ipairs(lines) do
    local row = first + i - 1
    local skip_dashes = is_rule_or_table_sep(line)

    -- closing hashes on ATX headings: "### Title ###"
    local close = line:match("^#+%s+.-()%s+#+%s*$")
    if close and not is_excluded(ranges, row, 0) then
      conceal(buf, row, close - 1, #line - close + 1, "")
    end

    -- ellipsis
    local init = 1
    while true do
      local s = line:find("...", init, true)
      if not s then
        break
      end
      if not is_excluded(ranges, row, s - 1) and line:sub(s + 3, s + 3) ~= "." and line:sub(s - 1, s - 1) ~= "." then
        conceal(buf, row, s - 1, 3, "…")
      end
      init = s + 3
    end

    -- em dash (---) and en dash / range (--)
    if not skip_dashes then
      init = 1
      while true do
        local s, e = line:find("%-%-+", init)
        if not s then
          break
        end
        local len = e - s + 1
        if (len == 2 or len == 3) and s > 1 and not is_excluded(ranges, row, s - 1) then
          conceal(buf, row, s - 1, len, len == 3 and "—" or "–")
        end
        init = e + 1
      end
    end

    -- inline html tags: <u>text</u>, <b>, <i>, <mark>, <kbd>, ...
    init = 1
    while true do
      local s, e, tag, inner = line:find("<(%a+)>(.-)</%1>", init)
      if not s then
        break
      end
      local hl = html_tags[tag:lower()]
      if hl and not is_excluded(ranges, row, s - 1) then
        local open, close = #tag + 2, #tag + 3
        conceal(buf, row, s - 1, open, "")
        conceal(buf, row, e - close, close, "")
        vim.api.nvim_buf_set_extmark(buf, ns, row, s - 1 + open, {
          end_col = s - 1 + open + #inner,
          hl_group = hl,
          priority = 150,
        })
      end
      init = e + 1
    end
  end

  -- indented code blocks get the code background
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if ok and parser then
    for _, tree in ipairs(parser:parse()) do
      local qok, query = pcall(vim.treesitter.query.parse, "markdown", "(indented_code_block) @c")
      if qok then
        for _, node in query:iter_captures(tree:root(), buf, first, last + 1) do
          local sr, _, er, ec = node:range()
          local stop = ec == 0 and er - 1 or er
          local first_line = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
          local base = #first_line:match("^%s*")
          local pending = {}
          for r = sr, stop do
            local text = vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1] or ""
            if text:match("^%s*$") then
              pending[#pending + 1] = r
            elseif #text:match("^%s*") >= base then
              pending[#pending + 1] = r
              for _, pr in ipairs(pending) do
                vim.api.nvim_buf_set_extmark(buf, ns, pr, 0, { line_hl_group = "RenderMarkdownCode", priority = 100 })
              end
              pending = {}
            else
              break
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------

---@class util.markdown.item
---@field indent string
---@field bullet? string
---@field num? integer
---@field delim? string
---@field checkbox boolean
---@field prefix string full prefix incl. marker and checkbox
---@field text string

---@return util.markdown.item?
function M.list_item(line)
  local indent, rest = line:match("^(%s*)(.*)$")
  local bullet = rest:match("^([-*+])%s")
  local num, delim = rest:match("^(%d+)([.)])%s")
  if not bullet and not num then
    return nil
  end
  local marker_len = bullet and 2 or (#num + 2)
  local after = rest:sub(marker_len + 1)
  local checkbox = after:match("^%[.%]%s") ~= nil or after:match("^%[.%]$") ~= nil
  local prefix = indent .. rest:sub(1, marker_len) .. (checkbox and after:sub(1, 4) or "")
  return {
    indent = indent,
    bullet = bullet,
    num = num and tonumber(num) or nil,
    delim = delim,
    checkbox = checkbox,
    prefix = prefix,
    text = line:sub(#prefix + 1),
  }
end

local function next_prefix(item, num)
  local marker = item.bullet or ((num or item.num + 1) .. item.delim)
  return item.indent .. marker .. " " .. (item.checkbox and "[ ] " or "")
end

--- Renumber consecutive numbered items at `indent`, starting at 1-based `row` with `from`.
local function renumber(buf, row, indent, from)
  local count = vim.api.nvim_buf_line_count(buf)
  local n = from
  for r = row, count do
    local line = vim.api.nvim_buf_get_lines(buf, r - 1, r, false)[1]
    if line:match("^%s*$") then
      break
    end
    local ind = line:match("^(%s*)")
    if #ind == #indent then
      local num, delim, rest = line:match("^%s*(%d+)([.)])(%s.*)$")
      if not num then
        break
      end
      if tonumber(num) ~= n then
        vim.api.nvim_buf_set_lines(buf, r - 1, r, false, { indent .. n .. delim .. rest })
      end
      n = n + 1
    elseif #ind < #indent then
      break
    end
  end
end

--- Insert-mode <CR> on a list item. Returns true when handled.
function M.list_enter()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local item = M.list_item(line)
  if not item then
    return false
  end
  if vim.trim(item.text) == "" then
    vim.api.nvim_set_current_line(item.indent)
    vim.api.nvim_win_set_cursor(0, { row, #item.indent })
    return true
  end
  col = math.max(col, #item.prefix)
  local new = next_prefix(item)
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line:sub(1, col), new .. line:sub(col + 1) })
  vim.api.nvim_win_set_cursor(0, { row + 1, #new })
  if item.num then
    renumber(0, row + 2, item.indent, item.num + 2)
  end
  return true
end

--- Normal-mode o / O on a list item. Returns true when handled.
function M.list_open(below)
  local row = vim.fn.line(".")
  local item = M.list_item(vim.api.nvim_get_current_line())
  if not item then
    return false
  end
  local new = next_prefix(item, item.num and (below and item.num + 1 or item.num) or nil)
  local at = below and row or row - 1
  vim.api.nvim_buf_set_lines(0, at, at, false, { new })
  local new_row = at + 1
  vim.api.nvim_win_set_cursor(0, { new_row, #new })
  if item.num then
    renumber(0, new_row + 1, item.indent, (below and item.num + 1 or item.num) + 1)
  end
  vim.cmd("startinsert!")
  return true
end

---------------------------------------------------------------------------
-- Headings
---------------------------------------------------------------------------

local function in_fence(buf, lnum)
  local node = node_at(buf, lnum - 1, 0)
  while node do
    if node:type() == "fenced_code_block" then
      return true
    end
    node = node:parent()
  end
  return false
end

function M.headings(buf)
  local out = {}
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local hashes, title = line:match("^(#+)%s+(.-)%s*#*$")
    if hashes and #hashes <= 6 and not in_fence(buf, i) then
      out[#out + 1] = { lnum = i, level = #hashes, title = title }
    end
  end
  return out
end

function M.jump_heading(dir)
  local buf = vim.api.nvim_get_current_buf()
  local cur = vim.fn.line(".")
  local target
  for _, h in ipairs(M.headings(buf)) do
    if dir > 0 and h.lnum > cur then
      target = h.lnum
      break
    elseif dir < 0 and h.lnum < cur then
      target = h.lnum
    end
  end
  if target then
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { target, 0 })
  end
end

function M.outline()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local items = {}
  for _, h in ipairs(M.headings(buf)) do
    items[#items + 1] = {
      text = string.rep("  ", h.level - 1) .. h.title,
      file = file,
      pos = { h.lnum, 0 },
      level = h.level,
    }
  end
  Snacks.picker.pick({
    title = "Headings",
    items = items,
    format = function(item)
      return { { item.text, "RenderMarkdownH" .. item.level } }
    end,
    preview = "file",
  })
end

---------------------------------------------------------------------------
-- Word count (statusline)
---------------------------------------------------------------------------

function M.wordcount()
  local wc = vim.fn.wordcount()
  local words = wc.visual_words or wc.words
  local minutes = math.max(1, math.ceil(wc.words / 200))
  return string.format("󰈭 %dw · %dm", words, minutes)
end

---------------------------------------------------------------------------
-- Keybind cheat sheet
---------------------------------------------------------------------------

local cheatsheet = {
  { "View" },
  { "<leader>um", "Toggle rendered / raw view" },
  { "<leader>mp", "Browser preview (toggle)" },
  { "<leader>mo", "Heading outline picker" },
  { "<leader>md", "This help" },
  { "Navigate" },
  { "j / k", "Move, skipping fences / table rules / hr" },
  { "]] / [[", "Next / previous heading" },
  { "za / zA", "Fold / unfold section" },
  { "<CR>", "Open link, else toggle checkbox, else move down" },
  { "Lists (insert)" },
  { "<CR>", "Continue list item (empty item ends the list)" },
  { "<Tab> / <S-Tab>", "Indent / outdent list item by 2" },
  { "o / O", "New list item below / above (normal)" },
  { "Syntax" },
  { "**b** *i* ~~s~~ ==hl==", "bold, italic, strike, highlight" },
  { "<u> <mark> <kbd>", "underline, highlight, key (inline html)" },
  { "... -- ---", "renders as … – —" },
  { "[^1]", "footnote (superscript)" },
  { "> [!NOTE]", "callout: NOTE TIP IMPORTANT WARNING CAUTION" },
  { "- [ ]  - [x]  - [-]", "checkbox: open, done, todo" },
}

function M.help()
  local lines, hls = {}, {}
  for _, row in ipairs(cheatsheet) do
    if row[2] then
      lines[#lines + 1] = string.format("  %-26s %s", row[1], row[2])
    else
      lines[#lines + 1] = ""
      lines[#lines + 1] = " " .. row[1]
      hls[#lines] = true
    end
  end
  table.remove(lines, 1)
  local shifted = {}
  for l in pairs(hls) do
    shifted[l - 1] = true
  end
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = width + 2
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for l in pairs(shifted) do
    vim.api.nvim_buf_add_highlight(buf, ns, "Title", l - 1, 0, -1)
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = #lines,
    row = math.max(math.floor((vim.o.lines - #lines) / 2) - 1, 0),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Markdown keys ",
    title_pos = "center",
  })
  vim.wo[win].conceallevel = 0
  for _, k in ipairs({ "q", "<Esc>", "<leader>md" }) do
    vim.keymap.set("n", k, "<cmd>close<cr>", { buffer = buf, nowait = true })
  end
end

---------------------------------------------------------------------------
-- Attach
---------------------------------------------------------------------------

local group = vim.api.nvim_create_augroup("md_extras", { clear = true })
local initialized = false

function M.attach(buf)
  if not initialized then
    initialized = true
    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  end

  -- window options
  vim.opt_local.wrap = true
  vim.opt_local.linebreak = true
  vim.opt_local.breakindent = true
  vim.opt_local.spell = true
  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
  vim.opt_local.foldlevel = 99

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end
  map("n", "]]", function()
    M.jump_heading(1)
  end, "Next heading")
  map("n", "[[", function()
    M.jump_heading(-1)
  end, "Previous heading")
  map("n", "<leader>mo", M.outline, "Markdown outline")
  map("n", "<leader>md", M.help, "Markdown keybind help")
  map("n", "o", function()
    if not M.list_open(true) then
      vim.api.nvim_feedkeys(vim.v.count1 .. "o", "n", false)
    end
  end, "New list item below")
  map("n", "O", function()
    if not M.list_open(false) then
      vim.api.nvim_feedkeys(vim.v.count1 .. "O", "n", false)
    end
  end, "New list item above")

  vim.api.nvim_create_autocmd(
    { "BufEnter", "TextChanged", "WinScrolled", "CursorHold", "BufWinEnter" },
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

return M
