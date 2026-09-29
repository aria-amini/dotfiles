return {
  { 'nvim-tree/nvim-web-devicons' },
  { 'nvim-mini/mini.icons', opts = {} },
  { 'NMAC427/guess-indent.nvim', opts = {} },
  { 'numToStr/Comment.nvim' },
  {
    'hedyhli/outline.nvim',
    config = function()
      -- Example mapping to toggle outline
      vim.keymap.set('n', '<leader>o', '<cmd>Outline<CR>', { desc = 'Toggle Outline' })
      require('outline').setup {
        symbols = {
          filter = {
            default = { 'Property', exclude = true },
          },
        },
      }
    end,
  },
  {
    'chrisgrieser/nvim-origami',
    event = 'VeryLazy',
    opts = {
      -- built-in autoFold disabled: it calls vim.lsp.foldclose before the LSP
      -- fold state exists, so it silently no-ops (see LspNotify autocmd below)
      autoFold = { enabled = false },
    },

    -- recommended: disable vim's auto-folding
    init = function()
      vim.opt.foldlevel = 99
      vim.opt.foldlevelstart = 99

      vim.api.nvim_create_autocmd('LspNotify', {
        desc = 'Autofold imports on file open',
        group = vim.api.nvim_create_augroup('autofold-imports', { clear = true }),
        callback = function(ctx)
          if ctx.data.method ~= 'textDocument/didOpen' then return end
          if vim.bo[ctx.buf].buftype ~= '' then return end
          vim.schedule(function()
            local client = vim.lsp.get_clients({ bufnr = ctx.buf, id = ctx.data.client_id })[1]
            if not client or not client:supports_method 'textDocument/foldingRange' then return end
            local winid = vim.fn.bufwinid(ctx.buf)
            if winid == -1 then return end
            local tries = 0
            local function try()
              if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= ctx.buf then return end
              tries = tries + 1
              local closed = vim.api.nvim_win_call(winid, function()
                vim.fn.foldlevel(1)
                pcall(vim.lsp.foldclose, 'imports', winid)
                return vim.fn.foldclosed(1)
              end)
              if closed == -1 and tries < 10 then vim.defer_fn(try, 200) end
            end
            try()
          end)
        end,
      })
    end,
  },
  {
    'folke/trouble.nvim',
    opts = {}, -- for default options, refer to the configuration section for custom setup.
    cmd = 'Trouble',
    keys = {
      {
        '<leader>xx',
        '<cmd>Trouble diagnostics toggle<cr>',
        desc = 'Diagnostics (Trouble)',
      },
      {
        '<leader>xX',
        '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
        desc = 'Buffer Diagnostics (Trouble)',
      },
      {
        '<leader>cs',
        '<cmd>Trouble symbols toggle focus=false<cr>',
        desc = 'Symbols (Trouble)',
      },
      {
        '<leader>cl',
        '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
        desc = 'LSP Definitions / references / ... (Trouble)',
      },
      {
        '<leader>xL',
        '<cmd>Trouble loclist toggle<cr>',
        desc = 'Location List (Trouble)',
      },
      {
        '<leader>xQ',
        '<cmd>Trouble qflist toggle<cr>',
        desc = 'Quickfix List (Trouble)',
      },
    },
  },
  {
    'nvim-pack/nvim-spectre',
    dependencies = { 'nvim-lua/plenary.nvim' },
    cmd = 'Spectre',
    keys = {
      {
        '<leader>sr',
        function() require('spectre').open() end,
        desc = 'Search and Replace',
      },
    },
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    opts = {},
  },
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    opts = {},
  },
  { -- Autocompletion
    'saghen/blink.cmp',
    event = 'VimEnter',
    version = '1.*',
    dependencies = {
      -- Snippet Engine
      {
        'L3MON4D3/LuaSnip',
        version = '2.*',
        build = (function()
          -- Build Step is needed for regex support in snippets.
          -- This step is not supported in many windows environments.
          -- Remove the below condition to re-enable on windows.
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then return end
          return 'make install_jsregexp'
        end)(),
        dependencies = {
          -- `friendly-snippets` contains a variety of premade snippets.
          --    See the README about individual language/framework/plugin snippets:
          --    https://github.com/rafamadriz/friendly-snippets
          -- {
          --   'rafamadriz/friendly-snippets',
          --   config = function()
          --     require('luasnip.loaders.from_vscode').lazy_load()
          --   end,
          -- },
        },
        opts = {},
      },
    },
    --- @module 'blink.cmp'
    --- @type blink.cmp.Config
    opts = {
      keymap = {
        -- 'default' (recommended) for mappings similar to built-in completions
        --   <c-y> to accept ([y]es) the completion.
        --    This will auto-import if your LSP supports it.
        --    This will expand snippets if the LSP sent a snippet.
        -- 'super-tab' for tab to accept
        -- 'enter' for enter to accept
        -- 'none' for no mappings
        --
        -- For an understanding of why the 'default' preset is recommended,
        -- you will need to read `:help ins-completion`
        --
        -- No, but seriously. Please read `:help ins-completion`, it is really good!
        --
        -- All presets have the following mappings:
        -- <tab>/<s-tab>: move to right/left of your snippet expansion
        -- <c-space>: Open menu or open docs if already open
        -- <c-n>/<c-p> or <up>/<down>: Select next/previous item
        -- <c-e>: Hide menu
        -- <c-k>: Toggle signature help
        --
        -- See :h blink-cmp-config-keymap for defining your own keymap
        preset = 'default',

        -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
        --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
      },

      appearance = {
        -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
        -- Adjusts spacing to ensure icons are aligned
        nerd_font_variant = 'mono',
      },

      completion = {
        -- By default, you may press `<c-space>` to show the documentation.
        -- Optionally, set `auto_show = true` to show the documentation after a delay.
        documentation = { auto_show = true, auto_show_delay_ms = 500 },
      },

      sources = {
        default = { 'lsp', 'path', 'snippets' },
      },

      snippets = { preset = 'luasnip' },

      -- Blink.cmp includes an optional, recommended rust fuzzy matcher,
      -- which automatically downloads a prebuilt binary when enabled.
      --
      -- By default, we use the Lua implementation instead, but you may enable
      -- the rust implementation via `'prefer_rust_with_warning'`
      --
      -- See :h blink-cmp-config-fuzzy for more information
      fuzzy = { implementation = 'lua' },

      -- Shows a signature help window while you type arguments for a function
      signature = { enabled = true },
    },
  },
  {
    'brenton-leighton/multiple-cursors.nvim',
    version = '*',
    opts = function()
      local clipboard
      return {
        pre_hook = function()
          clipboard = vim.opt.clipboard:get()
          vim.opt.clipboard = {}
        end,
        post_hook = function() vim.opt.clipboard = clipboard end,
      }
    end,
    keys = {
      { '<C-j>', '<Cmd>MultipleCursorsAddDown<CR>', mode = { 'n', 'x' }, desc = 'Add cursor and move down' },
      { '<C-k>', '<Cmd>MultipleCursorsAddUp<CR>', mode = { 'n', 'x' }, desc = 'Add cursor and move up' },
      { '<C-Up>', '<Cmd>MultipleCursorsAddUp<CR>', mode = { 'n', 'i', 'x' }, desc = 'Add cursor and move up' },
      { '<C-Down>', '<Cmd>MultipleCursorsAddDown<CR>', mode = { 'n', 'i', 'x' }, desc = 'Add cursor and move down' },
      { '<C-LeftMouse>', '<Cmd>MultipleCursorsMouseAddDelete<CR>', mode = { 'n', 'i' }, desc = 'Add or remove cursor' },
      { '<Leader>m', '<Cmd>MultipleCursorsAddVisualArea<CR>', mode = { 'x' }, desc = 'Add cursors to the lines of the visual area' },
      { '<Leader>a', '<Cmd>MultipleCursorsAddMatches<CR>', mode = { 'n', 'x' }, desc = 'Add cursors to cword' },
      { '<Leader>A', '<Cmd>MultipleCursorsAddMatchesV<CR>', mode = { 'n', 'x' }, desc = 'Add cursors to cword in previous area' },
      { '<Leader>d', '<Cmd>MultipleCursorsAddJumpNextMatch<CR>', mode = { 'n', 'x' }, desc = 'Add cursor and jump to next cword' },
      { '<Leader>D', '<Cmd>MultipleCursorsJumpNextMatch<CR>', mode = { 'n', 'x' }, desc = 'Jump to next cword' },
      { '<Leader>l', '<Cmd>MultipleCursorsLock<CR>', mode = { 'n', 'x' }, desc = 'Lock virtual cursors' },
    },
  },
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },
  {
    'nvim-mini/mini.nvim',
    config = function()
      require('mini.ai').setup { n_lines = 500 }
      require('mini.surround').setup()
      require('mini.sessions').setup()
      require('mini.diff').setup()
      local statusline = require 'mini.statusline'
      statusline.setup { use_icons = vim.g.have_nerd_font }

      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function() return '%2l:%-2v' end

      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_filename = function()
        local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ':~')
        local file = vim.fn.expand '%:t'
        if file == '' then return cwd end
        return cwd .. ' / ' .. file
      end
    end,
  },
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    opts = {
      -- add any options here
    },
    dependencies = {
      -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
      'MunifTanjim/nui.nvim',
      -- OPTIONAL:
      'nvim-notify',
      --   If not available, we use `mini` as the fallback
      'rcarriga/nvim-notify',
    },
    config = function()
      require('noice').setup {
        lsp = {
          -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
          override = {
            ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
            ['vim.lsp.util.stylize_markdown'] = true,
            ['cmp.entry.get_documentation'] = true, -- requires hrsh7th/nvim-cmp
          },
        },
        -- you can enable a preset for easier configuration
        presets = {
          bottom_search = true, -- use a classic bottom cmdline for search
          command_palette = true, -- position the cmdline and popupmenu together
          long_message_to_split = true, -- long messages will be sent to a split
          inc_rename = false, -- enables an input dialog for inc-rename.nvim
          lsp_doc_border = false, -- add a border to hover docs and signature help
        },
      }
    end,
  },
  {
    'mikavilpas/yazi.nvim',
    version = '*',
    event = 'VeryLazy',
    dependencies = {
      { 'nvim-lua/plenary.nvim', lazy = true },
    },
    keys = {
      {
        '-',
        mode = { 'n', 'v' },
        function()
          if vim.bo.modified then
            local choice = vim.fn.confirm(
              'Save changes to ' .. vim.fn.expand('%:.') .. '?',
              '&Save\n&Discard\n&Cancel',
              1
            )
            if choice == 3 then return end
            if choice == 1 then vim.cmd.write() end
          end
          vim.cmd.Yazi()
        end,
        desc = 'Open yazi at the current file',
      },
      {
        '_',
        '<cmd>Yazi cwd<cr>',
        desc = "Open the file manager in nvim's working directory",
      },
      {
        '<C-+>',
        '<cmd>Yazi toggle<cr>',
        desc = 'Resume the last yazi session',
      },
    },
    opts = {
      floating_window_scaling_factor = 1,
      open_for_directories = true,
      change_neovim_cwd_on_close = true,
      keymaps = {
        show_help = '<f1>',
      },
      hooks = {
        yazi_closed_successfully = function()
          local ok, dashboard = pcall(require, 'snacks.dashboard')
          if ok then dashboard.update() end
        end,
      },
    },
    init = function() vim.g.loaded_netrwPlugin = 1 end,
  },
  { -- Useful plugin to show you pending keybinds.
    'folke/which-key.nvim',
    event = 'VimEnter',
    opts = {
      -- delay between pressing a key and opening which-key (milliseconds)
      delay = 0,
      icons = { mappings = vim.g.have_nerd_font },

      -- Document existing key chains
      spec = {
        { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
      },
    },
  },

  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    -- By default, Telescope is included and acts as your picker for everything.

    -- If you would like to switch to a different picker (like snacks, or fzf-lua)
    -- you can disable the Telescope plugin by setting enabled to false and enable
    -- your replacement picker by requiring it explicitly (e.g. 'custom.plugins.snacks')

    -- Note: If you customize your config for yourself,
    -- it’s best to remove the Telescope plugin config entirely
    -- instead of just disabling it here, to keep your config clean.
    enabled = false,
    event = 'VimEnter',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { -- If encountering errors, see telescope-fzf-native README for installation instructions
        'nvim-telescope/telescope-fzf-native.nvim',

        -- `build` is used to run some command when the plugin is installed/updated.
        -- This is only run then, not every time Neovim starts up.
        build = 'make',

        -- `cond` is a condition used to determine whether this plugin should be
        -- installed and loaded.
        cond = function() return vim.fn.executable 'make' == 1 end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },

      -- Useful for getting pretty icons, but requires a Nerd Font.
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      -- Telescope is a fuzzy finder that comes with a lot of different things that
      -- it can fuzzy find! It's more than just a "file finder", it can search
      -- many different aspects of Neovim, your workspace, LSP, and more!
      --
      -- The easiest way to use Telescope, is to start by doing something like:
      --  :Telescope help_tags
      --
      -- After running this command, a window will open up and you're able to
      -- type in the prompt window. You'll see a list of `help_tags` options and
      -- a corresponding preview of the help.
      --
      -- Two important keymaps to use while in Telescope are:
      --  - Insert mode: <c-/>
      --  - Normal mode: ?
      --
      -- This opens a window that shows you all of the keymaps for the current
      -- Telescope picker. This is really useful to discover what Telescope can
      -- do as well as how to actually do it!

      -- [[ Configure Telescope ]]
      -- See `:help telescope` and `:help telescope.setup()`
      require('telescope').setup {
        -- You can put your default mappings / updates / etc. in here
        --  All the info you're looking for is in `:help telescope.setup()`
        --
        -- defaults = {
        --   mappings = {
        --     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
        --   },
        -- },
        pickers = {
          find_files = {
            hidden = true,
          },
        },
        extensions = {
          ['ui-select'] = { require('telescope.themes').get_dropdown() },
        },
      }

      -- Enable Telescope extensions if they are installed
      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      -- See `:help telescope.builtin`
      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader>sc', builtin.commands, { desc = '[S]earch [C]ommands' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

      -- This runs on LSP attach per buffer (see main LSP attach function in 'neovim/nvim-lspconfig' config for more info,
      -- it is better explained there). This allows easily switching between pickers if you prefer using something else!
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('telescope-lsp-attach', { clear = true }),
        callback = function(event)
          local buf = event.buf

          -- Find references for the word under your cursor.
          vim.keymap.set('n', 'grr', builtin.lsp_references, { buffer = buf, desc = '[G]oto [R]eferences' })

          -- Jump to the implementation of the word under your cursor.
          -- Useful when your language has ways of declaring types without an actual implementation.
          vim.keymap.set('n', 'gri', builtin.lsp_implementations, { buffer = buf, desc = '[G]oto [I]mplementation' })

          -- Jump to the definition of the word under your cursor.
          -- This is where a variable was first declared, or where a function is defined, etc.
          -- To jump back, press <C-t>.
          vim.keymap.set('n', 'grd', builtin.lsp_definitions, { buffer = buf, desc = '[G]oto [D]efinition' })

          -- Fuzzy find all the symbols in your current document.
          -- Symbols are things like variables, functions, types, etc.
          vim.keymap.set('n', 'gO', builtin.lsp_document_symbols, { buffer = buf, desc = 'Open Document Symbols' })

          -- Fuzzy find all the symbols in your current workspace.
          -- Similar to document symbols, except searches over your entire project.
          vim.keymap.set('n', 'gW', builtin.lsp_dynamic_workspace_symbols, { buffer = buf, desc = 'Open Workspace Symbols' })

          -- Jump to the type of the word under your cursor.
          -- Useful when you're not sure what type a variable is and you want to see
          -- the definition of its *type*, not where it was *defined*.
          vim.keymap.set('n', 'grt', builtin.lsp_type_definitions, { buffer = buf, desc = '[G]oto [T]ype Definition' })
        end,
      })

      -- Override default behavior and theme when searching
      vim.keymap.set('n', '<leader>/', function()
        -- You can pass additional configuration to Telescope to change the theme, layout, etc.
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      -- It's also possible to pass additional configuration options.
      --  See `:help telescope.builtin.live_grep()` for information about particular keys
      vim.keymap.set(
        'n',
        '<leader>s/',
        function()
          builtin.live_grep {
            grep_open_files = true,
            prompt_title = 'Live Grep in Open Files',
          }
        end,
        { desc = '[S]earch [/] in Open Files' }
      )

      -- Shortcut for searching your Neovim configuration files
      vim.keymap.set('n', '<leader>sn', function() builtin.find_files { cwd = vim.fn.stdpath 'config' } end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  {
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-mini/mini.nvim' },
    opts = {},
  },
  {
    'Shatur/neovim-ayu',
    priority = 1000,
    config = function()
      require('ayu').setup {
        terminal = true,
        overrides = {
          Normal = { bg = 'None' },
          NormalFloat = { bg = 'None' },
        },
      }
      vim.cmd.colorscheme('ayu-' .. require('theme').flavour)
    end,
  },
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    ---@type Flash.Config
    opts = {},
    keys = {
      { 's', mode = { 'n', 'x', 'o' }, function() require('flash').jump() end, desc = 'Flash' },
      { 'S', mode = { 'n', 'x', 'o' }, function() require('flash').treesitter() end, desc = 'Flash Treesitter' },
      { 'r', mode = 'o', function() require('flash').remote() end, desc = 'Remote Flash' },
      { 'R', mode = { 'o', 'x' }, function() require('flash').treesitter_search() end, desc = 'Treesitter Search' },
      { '<c-s>', mode = { 'c' }, function() require('flash').toggle() end, desc = 'Toggle Flash Search' },
    },
  },
  {
    'sphamba/smear-cursor.nvim',
    opts = {},
  },

  { 'vim-test/vim-test' },
}
