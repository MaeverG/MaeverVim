-- For `plugins/markview.lua` users.
return {
  "OXY2DEV/markview.nvim",
  lazy = false,
  commit = "aadb6d817577d553bbef61e8b9073f1bf4b87e08", -- pinned
  pin = true, -- never update via :Lazy update

  -- the `:toc:` block is rendered by `util.adoc` (selectable entries)
  opts = {
    renderers = { asciidoc_toc = function() end },
  },

  -- Completion for `blink.cmp`
  dependencies = { "saghen/blink.cmp" },
}
