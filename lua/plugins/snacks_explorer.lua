return {
  "folke/snacks.nvim",
  opts = {
    explorer = {},
    picker = {
      sources = {
        explorer = {
          actions = {
            -- open every file directly inside the hovered folder (max 20)
            open_dir_files = function(picker, item)
              if not (item and item.dir) then
                return picker:action("confirm")
              end
              local files = {}
              for name, type in vim.fs.dir(item.file) do
                if type == "file" then
                  files[#files + 1] = vim.fs.joinpath(item.file, name)
                end
              end
              table.sort(files)
              if #files == 0 then
                return vim.notify("No files in " .. item.file, vim.log.levels.INFO)
              end
              if #files > 20 then
                vim.notify("Opening first 20 of " .. #files .. " files", vim.log.levels.WARN)
              end
              for i = 1, math.min(#files, 20) do
                if i == 1 then
                  vim.api.nvim_win_call(picker.main, function()
                    vim.cmd.edit(vim.fn.fnameescape(files[i]))
                  end)
                else
                  vim.cmd.badd(vim.fn.fnameescape(files[i]))
                end
              end
            end,
          },
          win = {
            list = { keys = { ["<S-CR>"] = "open_dir_files" } },
          },
        },
      },
    },
  },
  keys = {
    {
      "<leader>fe",
      function()
        Snacks.explorer({ cwd = Util.root() })
      end,
      desc = "Explorer Snacks (root dir)",
    },
    {
      "<leader>fE",
      function()
        Snacks.explorer()
      end,
      desc = "Explorer Snacks (cwd)",
    },
    {
      "<leader>e",
      function()
        local p = Snacks.picker.get({ source = "explorer" })[1]
        if p and not p:is_focused() then
          p:focus()
        else
          Snacks.explorer({ cwd = Util.root() })
        end
      end,
      desc = "Explorer Snacks (focus or toggle)",
    },
    { "<leader>E", "<leader>fE", desc = "Explorer Snacks (cwd)", remap = true },
  },
}
