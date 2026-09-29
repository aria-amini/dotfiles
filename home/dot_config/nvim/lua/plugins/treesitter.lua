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
    vim.filetype.add({
      extension = {
        tmpl = function(path)
          local base = path:match('^(.*)%.tmpl$')
          local embedded = base and base:match('%.([%w]+)$')
          local known =
            { lua = 'lua', yaml = 'yaml', yml = 'yaml', toml = 'toml', json = 'json', jsonc = 'jsonc' }
          return (embedded and known[embedded]) or 'gotmpl'
        end,
      },
    })
    vim.api.nvim_create_autocmd('FileType', {
      pattern = parsers,
      callback = function(args) vim.treesitter.start(args.buf) end,
    })
  end,
}
