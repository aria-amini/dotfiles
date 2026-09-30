return { -- Highlight, edit, and navigate code
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    local parsers = {
      'bash', 'c', 'css', 'diff', 'gotmpl', 'html', 'javascript', 'json', 'lua',
      'luadoc', 'markdown', 'markdown_inline', 'python', 'query', 'toml', 'tsx',
      'typescript', 'vim', 'vimdoc', 'yaml',
    }
    require('nvim-treesitter').setup {}
    require('nvim-treesitter').install(parsers):wait(300000)
    vim.api.nvim_create_autocmd('FileType', {
      pattern = parsers,
      callback = function(args)
        -- chezmoi.vim provides regex template syntax for these; treesitter cannot
        if args.match:find 'chezmoitmpl' then return end
        vim.treesitter.start(args.buf)
      end,
    })
    -- Core ftplugins (e.g. ftplugin/lua.lua) component-match compound filetypes and
    -- start treesitter, which sets b:ts_highlight and blocks chezmoi.vim's syntax
    vim.api.nvim_create_autocmd('FileType', {
      pattern = '*',
      callback = function(args)
        if not args.match:find 'chezmoitmpl' then return end
        vim.treesitter.stop(args.buf)
        vim.b[args.buf].ts_highlight = nil
        vim.bo[args.buf].syntax = args.match
      end,
    })
  end,
}
