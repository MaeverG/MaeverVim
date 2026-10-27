-- Local copy of yt20chill/inline_git_blame.nvim (see lua/inline_git_blame.lua)
return {
  dir = vim.fn.stdpath("config"),
  name = "inline_git_blame",
  event = "BufReadPost",
  config = function()
    require("inline_git_blame").setup({})
  end,
  keys = {
    { "<leader>gb", function() require("inline_git_blame").inline_blame_current_line() end, desc = "Show inline git blame" },
    { "<leader>gB", function() require("inline_git_blame").clear_blame() end, desc = "Clear inline git blame" },
    { "<leader>gt", function() require("inline_git_blame").toggle_blame_current_line() end, desc = "Toggle inline git blame" },
  },
}
