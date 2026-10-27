# MaeverVim

My Neovim config, built on [LazyVim](https://github.com/LazyVim/LazyVim).

Highlights: rendered markdown (render-markdown.nvim) with checkbox/list/link helpers, heading outline,
word count, and a `<leader>md` cheat sheet of markdown keybinds.

## Install

```sh
git clone https://github.com/MaeverG/MaeverVim ~/.config/nvim
brew install neovim utftex   # utftex renders LaTeX math in markdown
nvim                         # lazy.nvim installs the plugins on first launch
```

Use a Nerd Font in your terminal. Inline images additionally need ImageMagick and a terminal with image support.

The previous multi-config layout (vim, tmux, zsh, old nvim) lives on the `legacy` branch.
