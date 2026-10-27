-- Searchable keybind list with a randomly chosen "keybind of the day"

---@param lhs string
local function pretty(lhs)
  return (lhs:gsub("^ ", "<leader>"))
end

--- Best-effort description for a keymap that doesn't have one
---@param k vim.api.keyset.get_keymap
local function fallback_desc(k)
  local rhs = k.rhs or ""
  if k.callback then
    local info = debug.getinfo(k.callback, "S")
    local src = info.what == "Lua" and vim.fn.fnamemodify(info.source:sub(2), ":t") or "builtin"
    return ("Lua function (%s:%d)"):format(src, info.linedefined or 0)
  end
  local plug = rhs:match("^<[Pp]lug>%(?([^)]*)%)?$")
  if plug then
    return "Plug: " .. plug
  end
  local cmd = rhs:match("^<[Cc][Mm][Dd]>(.-)<[Cc][Rr]>$") or rhs:match("^:(.-)<[Cc][Rr]>$")
  if cmd then
    return "Run :" .. cmd
  end
  return rhs ~= "" and ("Keys: " .. rhs) or "(no description)"
end

---@return {lhs:string, desc:string, mode:string}[]
local function candidates()
  local ret, seen = {}, {}
  for _, mode in ipairs({ "n", "x", "i", "t" }) do
    for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
      -- only user-facing leader keybinds, not Neovim's built-in defaults
      local desc = (map.desc and map.desc ~= "") and map.desc or fallback_desc(map)
      local skip = desc:find("which_key_ignore", 1, true) or not map.lhs:find("^ .")
      local id = mode .. map.lhs
      if not skip and not seen[id] then
        seen[id] = true
        ret[#ret + 1] = { lhs = pretty(map.lhs), desc = desc, mode = mode }
      end
    end
  end
  return ret
end

--- Row layout: category icon | mode | keys | description | command
---@param item snacks.picker.Item
local function format(item)
  local a = Snacks.picker.util.align
  local k = item.item
  local ret = {} ---@type snacks.picker.Highlight[]

  local ok, Icons = pcall(require, "which-key.icons")
  local icon, hl = nil, nil
  if ok then
    icon, hl = Icons.get({ keymap = k, desc = k.desc })
  end
  ret[#ret + 1] = icon and { a(icon, 3), hl } or { "   " }

  ret[#ret + 1] = { k.mode, "SnacksPickerKeymapMode" }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { a(Snacks.util.normkey(pretty(k.lhs)), 18), "SnacksPickerKeymapLhs" }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { a(k.desc or "", 38) }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { k.rhs and k.rhs ~= "" and k.rhs or "callback", "Comment" }
  return ret
end

return function()
  local from_dashboard = vim.bo.filetype == "snacks_dashboard"
  local list = candidates()
  local title = "Keybinds"
  if #list > 0 then
    math.randomseed(vim.uv.hrtime() % 2147483647)
    local pick = list[math.random(#list)]
    title = ("Keybinds  ·  Keybind of the day: %s  (%s)  %s"):format(pick.lhs, pick.mode, pick.desc)
    Snacks.notify.info(
      ("`%s` (%s mode)\n%s"):format(pick.lhs, pick.mode, pick.desc),
      { title = "Keybind of the day" }
    )
  end
  Snacks.picker.keymaps({
    title = title,
    format = format,
    -- Enter doesn't run the keybind: it closes the list and, if we came from
    -- the dashboard, makes sure we land back on it. From a document: do nothing.
    confirm = function(picker)
      picker:close()
      if from_dashboard then
        vim.schedule(function()
          if vim.bo.filetype ~= "snacks_dashboard" then
            Snacks.dashboard.open()
          end
        end)
      end
    end,
    -- give desc-less keymaps a generated description, and make it searchable
    transform = function(item)
      local k = item.item
      if not k.desc or k.desc == "" then
        k.desc = fallback_desc(k)
        item.text = item.text .. " " .. k.desc
      end
    end,
  })
end
