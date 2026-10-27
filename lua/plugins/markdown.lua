-- Render markdown in-buffer (headings, tables, code blocks) in normal mode;
-- raw text shows again in insert mode.

-- Lines that render as pure decoration (code fences, table separators, rules).
local function is_decoration(line)
  return line:match("^%s*```")
    or line:match("^%s*~~~")
    or line:match("^%s*|[%s:%-|+]+$") and line:find("-", 1, true)
    or line:match("^%s*%-%-%-+%s*$")
    or line:match("^%s*%*%*%*+%s*$")
    or line:match("^%s*___+%s*$")
end

local function rendering()
  local ok, state = pcall(require, "render-markdown.state")
  return ok and state.enabled ~= false
end

-- Link destinations "](url)" are concealed while rendered; keep word/char motions out of them.
local function hidden_range_at(line, col)
  local init = 1
  while true do
    local s, e = line:find("%]%([^)]*%)", init)
    if not s then
      return nil
    end
    if col >= s and col <= e then
      return s, e
    end
    init = e + 1
  end
end

local function skip_hidden(key, count)
  for _ = 1, count do
    vim.cmd("normal! " .. key)
    local guard = 0
    while guard < 50 do
      local s = hidden_range_at(vim.fn.getline("."), vim.fn.col("."))
      if not s then
        break
      end
      local before = vim.api.nvim_win_get_cursor(0)
      vim.cmd("normal! " .. key)
      guard = guard + 1
      if vim.deep_equal(before, vim.api.nvim_win_get_cursor(0)) then
        break
      end
    end
  end
end

local function step(dir, count)
  for _ = 1, count do
    local before = vim.fn.col(".")
    vim.cmd("normal! " .. (dir > 0 and "l" or "h"))
    local line = vim.fn.getline(".")
    local s, e = hidden_range_at(line, vim.fn.col("."))
    if s then
      local target = dir > 0 and e + 1 or s - 1 -- 1-based col just outside the hidden span
      if target < 1 or target > #line then
        target = before
      end
      vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), target - 1 })
    end
  end
end

-- j/k that hop over decoration lines (and still walk wrapped screen lines like gj/gk).
local function move(dir)
  local key = dir > 0 and "gj" or "gk"
  local last = vim.api.nvim_buf_line_count(0)
  for _ = 1, vim.v.count1 do
    vim.cmd("normal! " .. key)
    local guard = 0
    while is_decoration(vim.fn.getline(".")) and guard < 50 do
      local before = vim.api.nvim_win_get_cursor(0)
      vim.cmd("normal! " .. key)
      guard = guard + 1
      if vim.deep_equal(before, vim.api.nvim_win_get_cursor(0)) then
        break
      end
    end
    local lnum = vim.fn.line(".")
    if lnum < 1 or lnum > last then
      break
    end
  end
end

return {
  {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
  ft = { "markdown" },
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "markdown",
      callback = function(ev)
        -- Links on a line as { start, stop, url } (1-based, inclusive).
        local function links_in(line)
          local found = {}
          local function scan(pat, group)
            local init = 1
            while true do
              local s, e, url = line:find(pat, init)
              if not s then
                break
              end
              found[#found + 1] = { s, e, url }
              init = e + 1
            end
          end
          scan("%[[^%]]*%]%(([^)%s]+)[^)]*%)")
          scan("<(https?://[^>]+)>")
          scan("(https?://[^%s)>%]]+)")
          -- drop bare URLs already inside a [text](url) or <url>
          local out = {}
          for _, l in ipairs(found) do
            local nested = false
            for _, o in ipairs(found) do
              if o ~= l and o[1] <= l[1] and o[2] >= l[2] and (o[2] - o[1]) > (l[2] - l[1]) then
                nested = true
              end
            end
            if not nested then
              out[#out + 1] = l
            end
          end
          return out
        end

        -- <CR>: open link under cursor, else toggle a task checkbox, else open a lone link, else move down.
        vim.keymap.set("n", "<CR>", function()
          local lnum = vim.fn.line(".")
          local line = vim.fn.getline(lnum)
          local col = vim.fn.col(".")
          local links = links_in(line)
          for _, l in ipairs(links) do
            if col >= l[1] and col <= l[2] then
              return vim.ui.open(l[3])
            end
          end
          local is_task = line:match("^%s*[-*+]%s+%[.%]") or line:match("^%s*%d+[.)]%s+%[.%]")
          if #links == 1 and not is_task then
            return vim.ui.open(links[1][3])
          end
          local pre, mark, post = line:match("^(%s*[-*+]%s+%[)(.)(%].*)$")
          if not pre then
            pre, mark, post = line:match("^(%s*%d+[.)]%s+%[)(.)(%].*)$")
          end
          if pre and (mark == " " or mark == "x" or mark == "X") then
            vim.fn.setline(lnum, pre .. (mark == " " and "x" or " ") .. post)
          else
            vim.cmd("normal! " .. vim.v.count1 .. "j^")
          end
        end, { buffer = ev.buf, silent = true, desc = "Open link / toggle checkbox" })

        local function checkbox_parts(line)
          return require("util.markdown").list_item(line)
        end
        local function blink()
          local ok, cmp = pcall(require, "blink.cmp")
          return ok and cmp or nil
        end

        -- Insert <CR> on a list item: empty item -> remove marker; otherwise continue the list.
        vim.keymap.set("i", "<CR>", function()
          local cmp = blink()
          if cmp and cmp.is_visible() and cmp.accept() then
            return
          end
          if not require("util.markdown").list_enter() then
            vim.api.nvim_feedkeys(vim.keycode("<CR>"), "n", false)
          end
        end, { buffer = ev.buf, silent = true, desc = "Continue markdown list" })

        -- Insert <Tab>/<S-Tab> on a list row: indent/outdent by 2 spaces.
        local function shift(dir)
          local row, col = unpack(vim.api.nvim_win_get_cursor(0))
          local line = vim.api.nvim_get_current_line()
          if dir > 0 then
            vim.api.nvim_set_current_line("  " .. line)
            vim.api.nvim_win_set_cursor(0, { row, col + 2 })
          else
            local n = math.min(2, #line:match("^ *"))
            vim.api.nvim_set_current_line(line:sub(n + 1))
            vim.api.nvim_win_set_cursor(0, { row, math.max(col - n, 0) })
          end
        end
        vim.keymap.set("i", "<Tab>", function()
          if checkbox_parts(vim.api.nvim_get_current_line()) then
            return shift(1)
          end
          local cmp = blink()
          if cmp and (cmp.is_visible() and cmp.accept() or cmp.snippet_active() and cmp.snippet_forward()) then
            return
          end
          vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "n", false)
        end, { buffer = ev.buf, silent = true, desc = "Indent checkbox" })
        vim.keymap.set("i", "<S-Tab>", function()
          if checkbox_parts(vim.api.nvim_get_current_line()) then
            return shift(-1)
          end
          local cmp = blink()
          if cmp and cmp.snippet_active() and cmp.snippet_backward() then
            return
          end
          vim.api.nvim_feedkeys(vim.keycode("<S-Tab>"), "n", false)
        end, { buffer = ev.buf, silent = true, desc = "Outdent checkbox" })

        require("util.markdown").attach(ev.buf)

        for _, key in ipairs({ "w", "b", "e", "W", "B", "E" }) do
          vim.keymap.set("n", key, function()
            if rendering() then
              skip_hidden(key, vim.v.count1)
            else
              vim.cmd("normal! " .. vim.v.count1 .. key)
            end
          end, { buffer = ev.buf, silent = true, desc = "Motion, skipping hidden link URLs" })
        end
        for key, dir in pairs({ l = 1, h = -1 }) do
          vim.keymap.set("n", key, function()
            if rendering() then
              step(dir, vim.v.count1)
            else
              vim.cmd("normal! " .. vim.v.count1 .. key)
            end
          end, { buffer = ev.buf, silent = true, desc = "Move, skipping hidden link URLs" })
        end

        for key, dir in pairs({ j = 1, k = -1 }) do
          vim.keymap.set("n", key, function()
            -- Counts handled in move(); fall back to normal motion when rendering is off.
            if rendering() then
              move(dir)
            else
              vim.cmd("normal! " .. vim.v.count1 .. key)
            end
          end, { buffer = ev.buf, silent = true, desc = "Move, skipping markdown decoration" })
        end
      end,
    })
  end,
  opts = {
    -- hide native-concealed link URLs on the cursor line too (normal/command mode)
    win_options = { concealcursor = { rendered = "nc" } },
    render_modes = { "n", "c", "t" }, -- not "i"/"v", so editing and selecting show raw text
    -- keep everything rendered on the cursor line in normal mode (insert mode shows raw text)
    anti_conceal = { enabled = false },
    inline_highlight = { enabled = true }, -- ==highlight==
    html = { comment = { conceal = true } },
    heading = {
      sign = false,
      icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      width = "full",
      position = "inline",
      border = true,
      border_virtual = true,
      backgrounds = {
        "RenderMarkdownH1Bg",
        "RenderMarkdownH2Bg",
        "RenderMarkdownH3Bg",
        "RenderMarkdownH4Bg",
        "RenderMarkdownH5Bg",
        "RenderMarkdownH6Bg",
      },
    },
    code = {
      sign = false,
      style = "full",
      width = "block",
      left_pad = 1,
      right_pad = 1,
      min_width = 40,
      border = "thin", -- fences become thin virtual borders
      language_icon = true,
      language_name = true,
      inline_pad = 1,
    },
    bullet = { icons = { "●", "○", "◆", "◇" }, right_pad = 1 },
    checkbox = {
      unchecked = { icon = "󰄱 " },
      checked = { icon = "󰱒 ", scope_highlight = "@markup.strikethrough" },
      custom = {
        todo = { raw = "[-]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
      },
    },
    quote = { icon = "▋" },
    dash = { icon = "─", width = "full" },
    pipe_table = { preset = "round", style = "full", cell = "padded" },
    link = {
      enabled = true,
      footnote = { enabled = true, superscript = true, prefix = "", suffix = "" },
      wiki = { icon = "󱗖 " },
      image = "󰥶 ",
      email = "󰀓 ",
      hyperlink = "󰌹 ",
    },
    callout = {
      note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
      tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
      important = { raw = "[!IMPORTANT]", rendered = "󰅾 Important", highlight = "RenderMarkdownHint" },
      warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
      caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
    },
  },
  keys = {
    {
      "<leader>um",
      function()
        vim.cmd("RenderMarkdown toggle")
        vim.schedule(function()
          require("util.markdown").refresh()
          vim.cmd("redrawstatus")
        end)
      end,
      desc = "Toggle markdown render",
    },
  },
  },

  -- Live browser preview (images, mermaid, math)
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<cr>", ft = "markdown", desc = "Markdown browser preview" },
    },
  },
}
