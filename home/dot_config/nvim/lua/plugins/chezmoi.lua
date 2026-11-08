return { -- Treat chezmoi source files as their resolved targets, with template syntax on top
  'alker0/chezmoi.vim',
  lazy = false,
  init = function()
    vim.g['chezmoi#use_tmp_buffer'] = true
    local ok, out = pcall(vim.fn.system, { 'chezmoi', 'source-path' })
    if ok and vim.v.shell_error == 0 and out ~= '' then vim.g['chezmoi#source_dir_path'] = vim.fn.trim(out) end
  end,
  config = function()
    -- Worktrees of this repo: herdr's (dotfiles), worktrunk's and T3's (named after the repo folder).
    local pattern = {}
    for _, root in ipairs { '~/.herdr/workspaces/dotfiles', '~/.herdr/workspaces/chezmoi', '~/.t3/worktrees/chezmoi', '~/.t3/worktrees/dotfiles' } do
      local worktrees = vim.fn.expand(root) .. '/*'
      vim.list_extend(pattern, { worktrees .. '/*', worktrees .. '/*/*', worktrees .. '/*/**' })
    end
    vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
      pattern = pattern,
      callback = function() vim.fn['chezmoi#filetype#handle_chezmoi_filetype']() end,
    })
  end,
}
