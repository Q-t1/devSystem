# Fully declarative Neovim IDE (nixvim), the editor half of the coding-ide
# module (see ./default.nix for the yazi + zellij workspace around it).
#
# Goal: an IntelliJ-class editor for Nix / JSON / YAML / kustomize / Helm /
# Kubernetes descriptors. Every plugin is pinned by the `nixvim` flake input —
# there is no runtime plugin manager (no lazy.nvim, no Mason). All language
# servers, formatters and linters are provided from nixpkgs on Neovim's PATH,
# which is the only thing that works reliably on NixOS.
{
  inputs,
  pkgs,
  lib,
  config,
  profile,
  kind,
  ...
}:

let
  # How Neovim reaches the system clipboard. Set by the profile via the
  # `programs.codingIde.clipboardProvider` option (declared in default.nix):
  # "wsl" bridges to Windows (WSLg), "pbcopy" is macOS' native clipboard,
  # "osc52" uses terminal escapes that work headless / over SSH (remote
  # containers), "none" leaves autodetection be.
  clipboardProvider = config.programs.codingIde.clipboardProvider;

  # WSL: try the fast native Wayland path (wl-copy/wl-paste) and fall back to
  # the always-present Windows tools (clip.exe / PowerShell Get-Clipboard),
  # since WSLg's Wayland socket isn't always reachable (detached shells, some
  # multiplexer contexts return "connection refused").
  wslClipboardLua = ''
    local function wsl_copy(lines)
      local text = table.concat(lines, "\n")
      vim.fn.system({ "wl-copy", "--type", "text/plain" }, text)
      if vim.v.shell_error ~= 0 then
        vim.fn.system({ "clip.exe" }, text)
      end
    end
    local function wsl_paste()
      local out = vim.fn.systemlist({ "wl-paste", "--no-newline" })
      if vim.v.shell_error ~= 0 then
        out = vim.fn.systemlist({ "powershell.exe", "-NoProfile", "-Command", "Get-Clipboard" })
        for i, line in ipairs(out) do
          out[i] = (line:gsub("\r$", ""))
        end
        if #out > 0 and out[#out] == "" then
          table.remove(out)
        end
      end
      return out
    end
    vim.g.clipboard = {
      name = "wsl-native-fallback",
      copy = { ["+"] = wsl_copy, ["*"] = wsl_copy },
      paste = { ["+"] = wsl_paste, ["*"] = wsl_paste },
    }
  '';

  # macOS: pbcopy/pbpaste are always present and talk to the real system
  # clipboard, so no terminal round-trip (OSC 52) is needed — and unlike OSC 52,
  # paste works too.
  pbcopyClipboardLua = ''
    vim.g.clipboard = {
      name = "pbcopy",
      copy = {
        ["+"] = { "pbcopy" },
        ["*"] = { "pbcopy" },
      },
      paste = {
        ["+"] = { "pbpaste" },
        ["*"] = { "pbpaste" },
      },
      cache_enabled = 0,
    }
  '';

  # OSC 52: the terminal emulator owns the clipboard, so yank works with no
  # display server — the right choice inside a headless container reached over
  # a terminal. Paste over OSC 52 needs terminal support; where it is missing,
  # `"+p` simply no-ops (yank still works).
  osc52ClipboardLua = ''
    local osc52 = require("vim.ui.clipboard.osc52")
    vim.g.clipboard = {
      name = "OSC 52",
      copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
      paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
    }
  '';

  clipboardLua =
    {
      wsl = wslClipboardLua;
      pbcopy = pbcopyClipboardLua;
      osc52 = osc52ClipboardLua;
      none = "";
    }
    .${clipboardProvider};

  # vscode-langservers-extracted 4.10.0 ships a broken JSON server bundle: it
  # mixes CommonJS `require()` with a lone `import.meta.url`, so Node 24 can run
  # it as neither (as ESM `require` is undefined; as CJS `import.meta` is a
  # syntax error) and jsonls crashes at startup. Pin the bundle to CommonJS and
  # rewrite that one ESM-ism to its CJS equivalent.
  jsonlsFixed = pkgs.vscode-langservers-extracted.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      srv="$out/lib/node_modules/vscode-langservers-extracted/lib/json-language-server/node"
      echo '{ "type": "commonjs" }' > "$srv/package.json"
      substituteInPlace "$srv/jsonServerMain.js" \
        --replace-fail 'import.meta.url' "require('url').pathToFileURL(__filename).href"
    '';
  });
in
{
  imports = [ inputs.nixvim.homeModules.nixvim ];

  # The shared base (config/common/home.nix) enables programs.neovim, which also
  # wants to own ~/.config/nvim. nixvim manages that directory itself, so turn
  # the plain neovim module off here to avoid a collision.
  programs.neovim.enable = lib.mkForce false;

  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # Nixvim builds its plugins from this nixpkgs. Pin it explicitly to our
    # (followed) nixpkgs so nixvim stops warning that the input `follows`
    # diverges from its own tested pin.
    nixpkgs.source = inputs.nixpkgs;

    # Make "+/"* the default yank/paste registers so plain y/p use the system
    # clipboard. The provider itself (vim.g.clipboard) is defined in
    # extraConfigLua so it can fall back from wl-copy to clip.exe when WSLg's
    # Wayland socket isn't reachable.
    clipboard.register = "unnamedplus";

    globals = {
      mapleader = " ";
      maplocalleader = " ";

      # vim-visual-multi: bind VSCode's Ctrl-d ("select next occurrence") and
      # Ctrl-shift-l ("select all occurrences") to the multi-cursor engine.
      VM_maps = {
        "Find Under" = "<C-d>";
        "Find Subword Under" = "<C-d>";
        "Select All" = "<C-S-l>";
      };
      VM_show_warnings = 0;

      # yazi is the file manager (its own left zellij pane); disable netrw so
      # `nvim <dir>` doesn't open a directory buffer (on 0.12 `gx` uses
      # vim.ui.open, not netrw, so nothing is lost).
      loaded_netrw = 1;
      loaded_netrwPlugin = 1;
    };

    opts = {
      number = true;
      relativenumber = false; # VSCode shows absolute line numbers

      # Full mouse support: resize/scroll/select/click across every mode.
      # Windows Terminal already passes mouse events through by default.
      mouse = "a";

      expandtab = true;
      shiftwidth = 2;
      tabstop = 2;
      softtabstop = 2;
      smartindent = true;

      background = "dark";
      termguicolors = true;
      signcolumn = "yes";
      cursorline = true;
      scrolloff = 4;
      wrap = false;

      ignorecase = true;
      smartcase = true;

      undofile = true;
      autoread = true; # pick up external edits (Claude, git checkout); see checktime autocmd
      splitright = true;
      splitbelow = true;

      # Always show the tabline so open files are visible as horizontal tabs at
      # the top of the editor pane (files arrive via --remote-tab from yazi/fif).
      showtabline = 2;

      # Spell checking is turned on per-filetype (markdown/gitcommit/text) by an
      # autocmd in extraConfigLua, not globally — code buffers stay quiet. These
      # just configure it: `camel` splits CamelCase so identifiers in prose are
      # checked word-by-word instead of flagged whole.
      spelllang = "en";
      spelloptions = "camel";

      updatetime = 200;
      timeoutlen = 300;
    };

    # Catppuccin Mocha (the dark flavour). Its default integrations already
    # style telescope, bufferline, gitsigns, blink-cmp, trouble,
    # navic/barbecue, notify, indent-blankline, treesitter & which-key, so the
    # whole IDE follows the theme without per-plugin wiring. Catppuccin
    # italicises comments by default (parity with the old vscode theme), and
    # term_colors themes the toggleterm / :terminal palette to match.
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "mocha";
        term_colors = true;
      };
    };

    plugins = {
      # ---- UI / look & feel -------------------------------------------------
      web-devicons.enable = true; # needs a Nerd Font in the terminal
      which-key.enable = true;
      indent-blankline.enable = true;
      todo-comments.enable = true;
      fidget.enable = true; # LSP progress spinner
      barbecue.enable = true; # VSCode-style breadcrumb bar (winbar)
      navic.enable = true; # symbol context feeding the breadcrumbs
      notify.enable = true; # VSCode-style toast notifications
      rainbow-delimiters.enable = true; # bracket-pair colorization

      # nvim-colorizer: render hex / rgb / named colors as inline swatches. Most
      # useful on the theme values scattered through these configs (#cba6f7 …),
      # so you see the actual color while editing catppuccin/zjstatus palettes.
      colorizer.enable = true;

      lualine = {
        enable = true;
        settings = {
          options.theme = "auto"; # follow the active (catppuccin) colorscheme
          # Make the diagnostics counter a first-class, always-visible indicator
          # (error/warn/info/hint with the same Nerd Font glyphs as the gutter
          # signs) and show which LSP client is attached, so "is the server even
          # running?" is answerable at a glance. Otherwise mirrors the default
          # section layout.
          sections = {
            lualine_b = [
              "branch"
              "diff"
            ];
            lualine_c = [
              "filename"
              {
                __unkeyed-1 = "diagnostics";
                sources = [ "nvim_diagnostic" ];
                symbols = {
                  error = " ";
                  warn = " ";
                  info = " ";
                  hint = " ";
                };
                update_in_insert = false;
              }
            ];
            lualine_x = [
              # Names of the LSP clients attached to the current buffer, or a
              # muted "no LSP" when none — the at-a-glance "is a server live?".
              {
                __unkeyed-1.__raw = ''
                  function()
                    local names = {}
                    for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
                      names[#names + 1] = c.name
                    end
                    if #names == 0 then return "no LSP" end
                    return " " .. table.concat(names, ",")
                  end
                '';
              }
              "encoding"
              "filetype"
            ];
          };
        };
      };

      # ---- Navigation -------------------------------------------------------
      # The file manager is yazi, running as its own persistent left zellij pane
      # (see home.nix). It opens files here over a socket, so nothing about the
      # tree lives in this file. Telescope stays for fuzzy find / grep / symbols.

      # flash.nvim: label-based on-screen jumps (the IntelliJ/AceJump motion).
      # `s` + two chars labels every match to hop anywhere visible; `S` jumps by
      # treesitter node. Keymaps wired in extraConfigLua so `S` can skip visual
      # mode (nvim-surround owns visual `S`).
      flash.enable = true;

      # aerial.nvim: a persistent symbol outline (functions/keys/types) for the
      # current file — the panel complement to telescope's one-shot symbol
      # picker. Toggled with <leader>co. Fed by treesitter/LSP (both enabled).
      aerial.enable = true;

      telescope = {
        enable = true;
        extensions.fzf-native.enable = true;
        keymaps = {
          "<leader><space>" = "find_files";
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>fb" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fd" = "diagnostics";
          "<leader>fs" = "lsp_document_symbols";
          "<leader>fr" = "oldfiles"; # recently opened files (VSCode's recent)
          "<leader>fR" = "resume"; # reopen the last picker with its results
        };
      };

      # ---- Editing ----------------------------------------------------------
      nvim-autopairs.enable = true;
      nvim-surround.enable = true;
      comment.enable = true;

      # Integrated terminal panel at the bottom (VSCode's Ctrl-` panel).
      # Opened with <leader>t (Space t) — Windows Terminal can't deliver
      # Ctrl-` to a WSL app, so the panel is bound to a leader key instead.
      toggleterm = {
        enable = true;
        settings = {
          direction = "horizontal";
          size = 14;
        };
      };

      # ---- Git --------------------------------------------------------------
      # diffview.nvim: a proper side-by-side diff with a file-tree panel, plus
      # per-file and per-branch commit history — the reviewing/history half of
      # the git workflow (lazygit on <leader>gg stays the staging/commit half).
      # Opened with <leader>gv / <leader>gh (see keymaps).
      diffview.enable = true;

      # Signs in the gutter, plus buffer-local hunk keymaps wired via on_attach
      # (so they only bind in git-tracked buffers). Uses gitsigns' current
      # nav_hunk API — next_hunk/prev_hunk are @deprecated on 2.x and would emit
      # a toast now that nvim-notify intercepts vim.notify. Full git workflow
      # (stage/commit/branch) is lazygit on <leader>gg (see extraConfigLua).
      gitsigns = {
        enable = true;
        settings.on_attach.__raw = ''
          function(bufnr)
            local gs = require("gitsigns")
            local function map(mode, lhs, rhs, desc)
              vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
            end
            -- Hunk navigation (respect Vim's builtin ]c/[c while in diff mode).
            map("n", "]c", function()
              if vim.wo.diff then vim.cmd.normal({ "]c", bang = true }) else gs.nav_hunk("next") end
            end, "Next hunk")
            map("n", "[c", function()
              if vim.wo.diff then vim.cmd.normal({ "[c", bang = true }) else gs.nav_hunk("prev") end
            end, "Prev hunk")
            -- Stage/reset (stage_hunk toggles staging on 2.x — no separate undo).
            map("n", "<leader>gs", gs.stage_hunk, "Stage hunk")
            map("v", "<leader>gs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Stage selection")
            map("n", "<leader>gr", gs.reset_hunk, "Reset hunk")
            map("v", "<leader>gr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Reset selection")
            map("n", "<leader>gS", gs.stage_buffer, "Stage buffer")
            map("n", "<leader>gp", gs.preview_hunk, "Preview hunk")
            map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")
            map("n", "<leader>gd", gs.diffthis, "Diff this")
          end
        '';
      };

      # ---- Syntax / structure ----------------------------------------------
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };
      treesitter-context.enable = true;

      # ---- Markdown reading -------------------------------------------------
      # render-markdown.nvim turns a raw `.md` buffer into a formatted document
      # in place — headings get icons/backgrounds, fenced code blocks a filled
      # box with the language name, tables are aligned, bullets/checkboxes/
      # callouts are drawn. It follows catppuccin automatically and drives the
      # `markdown` + `markdown_inline` treesitter parsers (installed with the
      # grammar set above) plus web-devicons (enabled above), so nothing extra
      # is needed. anti_conceal shows the raw source only on the cursor's line,
      # so the file stays fully editable while everything else reads rendered.
      # Toggle raw/rendered on <leader>cm (see keymaps).
      render-markdown = {
        enable = true;
        settings = {
          anti_conceal.enabled = true;
          code = {
            style = "full"; # background box + language label on fenced blocks
            width = "block";
            left_pad = 2;
            right_pad = 2;
          };
          # These are Nix/k8s config docs, not math — skip LaTeX rendering so it
          # never warns about a missing `latex` parser / pylatexenc at :checkhealth.
          latex.enabled = false;
        };
      };

      # ---- Session ----------------------------------------------------------
      # persistence.nvim: save the open tabs/buffers per directory and restore
      # them when the IDE is relaunched on that project (see the VimEnter hook
      # in extraConfigLua). Makes a resurrected zellij `coding` session reopen
      # where it left off instead of a blank editor.
      persistence.enable = true;

      # ---- Diagnostics ------------------------------------------------------
      trouble.enable = true;

      # ---- Completion -------------------------------------------------------
      luasnip.enable = true;
      friendly-snippets.enable = true;
      blink-cmp = {
        enable = true;
        settings = {
          keymap.preset = "default";
          sources.default = [
            "lsp"
            "path"
            "snippets"
            "buffer"
          ];
          completion.documentation.auto_show = true;
          signature.enabled = true;
        };
      };

      # ---- LSP --------------------------------------------------------------
      lsp = {
        enable = true;
        servers = {
          # Nix. Point nixd at this flake so option completion/hover is the
          # real thing: `nixos.options` drives configuration.nix files and
          # `home-manager.options` drives home.nix files, so typing `programs.`
          # here completes against the modules actually in scope. Scoped to
          # *this* profile's own config since the module is shared across hosts,
          # and which output holds it depends on the profile's kind: NixOS hosts
          # embed Home Manager under `nixosConfigurations.<profile>`, while a
          # standalone host (macos) is a bare `homeConfigurations.<profile>`
          # with no NixOS options at all. `${inputs.self}` is the flake's store
          # path — option *names* come from the modules, not your values, so a
          # pinned snapshot is fine; nixpkgs.expr uses the flake's pinned nixpkgs.
          nixd = {
            enable = true;
            settings = {
              nixpkgs.expr = ''import (builtins.getFlake "${inputs.self}").inputs.nixpkgs { }'';
              options =
                if kind == "nixos" then
                  {
                    nixos.expr = ''(builtins.getFlake "${inputs.self}").nixosConfigurations.${profile}.options'';
                    home-manager.expr = ''(builtins.getFlake "${inputs.self}").nixosConfigurations.${profile}.options.home-manager.users.type.getSubOptions [ ]'';
                  }
                else
                  {
                    home-manager.expr = ''(builtins.getFlake "${inputs.self}").homeConfigurations.${profile}.options'';
                  };
            };
          };

          # YAML — schema-aware validation for Kubernetes / kustomize manifests.
          # keyOrdering=false stops it from demanding alphabetical keys, and the
          # bundled SchemaStore gives kube/CRD/CI completion out of the box.
          yamlls = {
            enable = true;
            settings.yaml = {
              keyOrdering = false;
              validate = true;
              format.enable = false; # prettier owns formatting (see conform)
              schemaStore.enable = true;
            };
          };

          # JSON / JSONC (with SchemaStore catalog). The stock server package
          # crashes under Node, so use the patched build (see jsonlsFixed).
          jsonls = {
            enable = true;
            package = jsonlsFixed;
          };

          # Lua (for editing this very config)
          lua_ls.enable = true;

          # Shell
          bashls.enable = true;

          # Docker — you run Docker in this WSL profile; completion/hover for
          # Dockerfile directives and image references.
          dockerls.enable = true;

          # TOML (starship.toml, Cargo, CI configs). taplo also formats TOML —
          # wired into conform below.
          taplo.enable = true;

          # Markdown — cross-file link/heading completion and go-to-definition
          # for the docs in these repos, complementing render-markdown's
          # in-buffer rendering.
          marksman.enable = true;
        };
        keymaps = {
          lspBuf = {
            "gd" = "definition";
            "gD" = "declaration";
            "gr" = "references";
            "gi" = "implementation";
            "gy" = "type_definition";
            "K" = "hover";
            "<leader>cr" = "rename";
            "<leader>ca" = "code_action";
          };
          diagnostic = {
            "]d" = "goto_next";
            "[d" = "goto_prev";
            "<leader>cd" = "open_float";
          };
        };
      };

      # ---- Formatting (format-on-save) -------------------------------------
      conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft = {
            nix = [ "nixfmt" ];
            yaml = [ "prettierd" ];
            json = [ "prettierd" ];
            jsonc = [ "prettierd" ];
            markdown = [ "prettierd" ];
            lua = [ "stylua" ];
            sh = [ "shfmt" ];
            toml = [ "taplo" ];
          };
          format_on_save = {
            lsp_format = "fallback";
            timeout_ms = 1500;
          };
        };
      };

      # ---- Linting ----------------------------------------------------------
      lint = {
        enable = true;
        lintersByFt = {
          yaml = [ "yamllint" ];
        };
      };
    };

    # Helm charts: towolf/vim-helm sets filetype=helm for templates so the YAML
    # server does not choke on Go templating, and helm-ls (wired below) provides
    # completion/hover for chart values.
    extraPlugins = with pkgs.vimPlugins; [
      vim-helm
      vim-visual-multi # VSCode-style multi-cursor (Ctrl-d)
      claudecode-nvim # Claude Code IDE integration (like the VSCode extension)
      grug-far-nvim # VSCode-style project-wide find & replace (Search panel)
    ];

    # nixvim has no helm_ls option, so register it with Neovim's built-in LSP
    # API. The older `require('lspconfig').helm_ls.setup()` framework is
    # deprecated on 0.11+; its warning would otherwise pop up as a startup
    # toast now that nvim-notify intercepts vim.notify.
    extraConfigLua = ''
      vim.lsp.config("helm_ls", {
        cmd = { "helm_ls", "serve" },
        filetypes = { "helm" },
        root_markers = { "Chart.yaml" },
        settings = {
          ["helm-ls"] = {
            yamlls = { path = "yaml-language-server" },
          },
        },
      })
      vim.lsp.enable("helm_ls")

      -- The file manager is yazi, running as its own persistent left zellij pane
      -- (see home.nix: the `coding` layout). Neovim starts with --listen on a
      -- session-scoped socket; yazi/fif open files via --remote-tab so they appear
      -- as nvim tabs in the tabline at the top of the editor pane. <S-h>/<S-l>
      -- navigate nvim tabs; <C-b>/<leader>e move focus to the yazi pane.

      -- When the first file arrives via --remote-tab, Neovim opens a new tab
      -- beside the initial empty scratch. Close the scratch so only real file
      -- tabs remain. `once = true` makes the autocmd self-remove after firing.
      vim.api.nvim_create_autocmd("TabNewEntered", {
        desc = "Close initial empty scratch tab on first file open",
        once = true,
        callback = function()
          if vim.fn.tabpagenr() == 2 then
            local win = vim.fn.tabpagewinnr(1)
            local buf = vim.fn.tabpagebuflist(1)[win]
            if vim.api.nvim_buf_get_name(buf) == "" then
              vim.cmd("1tabclose")
            end
          end
        end,
      })

      -- Claude Code integration — mirrors the VSCode/JetBrains extension:
      -- shared selection, in-editor diffs, and a `claude` terminal. auto_start
      -- is off so the WebSocket bridge only comes up when you open Claude.
      require("claudecode").setup({
        auto_start = false,
        terminal = {
          provider = "native",
          split_side = "right",
          split_width_percentage = 0.35,
        },
      })

      -- Name the surrounding zellij tab after the project whenever the IDE is
      -- opened on one, so tabs read "config-manager" instead of zellij's
      -- default "Tab #1". Prefer the git repo root's name, falling back to the
      -- directory's. Scoped to the "opened on a project" cases (a bare `nvim` or
      -- `nvim <dir>`) so single-file $EDITOR use (git commit, kubectl edit)
      -- leaves the tab name alone, and a no-op outside zellij. Async so it never
      -- blocks startup.
      vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Name the zellij tab after the project",
        callback = function()
          if vim.env.ZELLIJ == nil then
            return
          end
          local argc = vim.fn.argc()
          local opened_dir = argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1
          if argc ~= 0 and not opened_dir then
            return
          end
          local base = opened_dir and vim.fn.fnamemodify(vim.fn.argv(0), ":p") or vim.uv.cwd()
          base = base:gsub("/$", "")
          local root = vim.fs.root(base, ".git")
          local name = vim.fs.basename(root or base)
          if name and name ~= "" then
            vim.system({ "zellij", "action", "rename-tab", name })
          end
        end,
      })

      -- Project-wide find & replace, editable in place (VSCode's Ctrl-Shift-F
      -- Search panel). Opens a buffer listing every match across the project;
      -- edit the "Replace" line and :w / <leader>sr-apply to rewrite all files.
      require("grug-far").setup({})

      -- VSCode-style: a single left click in an editable file drops you
      -- straight into insert ("edit") mode. Guarded to normal file buffers so
      -- it never fires in the terminal or other special windows;
      -- bound in normal mode only so click-drag text selection still works
      -- (a drag ends in visual mode, where this mapping does not apply).
      vim.keymap.set("n", "<LeftRelease>", function()
        if vim.bo.buftype == "" and vim.bo.modifiable and not vim.bo.readonly then
          vim.cmd("startinsert")
        end
      end, { desc = "Click to edit (enter insert mode)" })

      -- System-clipboard bridge, chosen per profile (see clipboardProvider in
      -- the let block: WSL → Windows tools, macOS → pbcopy/pbpaste, headless
      -- containers → OSC 52 terminal escapes).
      ${clipboardLua}

      -- Select-to-copy: releasing a mouse drag-selection yanks it to the system
      -- clipboard, so selecting with the mouse copies like a terminal/VSCode do.
      vim.keymap.set("x", "<LeftRelease>", '"+y', { desc = "Copy mouse selection" })

      -- Seamless window/pane navigation across Neovim splits and zellij panes.
      -- Ctrl-h/j/k/l moves between Neovim splits; at the outermost split it hops
      -- to the adjacent zellij pane instead, so the two read as one continuous
      -- space (the zellij analogue of vim-tmux-navigator). Moving *into* Neovim
      -- from another zellij pane uses zellij's own Alt-h/j/k/l — in a shell pane
      -- Ctrl-h is backspace, so it can't be the universal mover. The zellij keys
      -- that would otherwise shadow these Ctrl chords are freed in home.nix.
      local function zellij_nav(nvim_dir, zellij_dir)
        local before = vim.api.nvim_get_current_win()
        vim.cmd.wincmd(nvim_dir)
        if before == vim.api.nvim_get_current_win() then
          vim.fn.system({ "zellij", "action", "move-focus", zellij_dir })
        end
      end
      for _, m in ipairs({
        { "h", "left" },
        { "j", "down" },
        { "k", "up" },
        { "l", "right" },
      }) do
        vim.keymap.set("n", "<C-" .. m[1] .. ">", function()
          zellij_nav(m[1], m[2])
        end, { desc = "Navigate window/pane " .. m[2] })
      end

      -- Inline diagnostics UX. Neovim's defaults leave virtual text off, so
      -- errors only show in the gutter/float; turn on IntelliJ-style inline
      -- messages, sort by severity so the worst wins a line, and give floats a
      -- border. Nerd Font sign glyphs (the terminal already has one for
      -- web-devicons) replace the default letters.
      vim.diagnostic.config({
        severity_sort = true,
        underline = true,
        update_in_insert = false,
        virtual_text = { spacing = 2, source = "if_many", prefix = "●" },
        float = { border = "rounded", source = true },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "",
            [vim.diagnostic.severity.WARN] = "",
            [vim.diagnostic.severity.INFO] = "",
            [vim.diagnostic.severity.HINT] = "",
          },
        },
      })

      -- Inlay hints (parameter names, inferred types) — the closest thing to
      -- VSCode/IntelliJ hints. Enabled per-buffer on attach; servers that don't
      -- implement them simply render nothing, so no capability check is needed.
      -- <leader>ch toggles them when they get noisy.
      vim.api.nvim_create_autocmd("LspAttach", {
        desc = "Enable LSP inlay hints",
        callback = function(args)
          if vim.lsp.inlay_hint then
            pcall(vim.lsp.inlay_hint.enable, true, { bufnr = args.buf })
          end
        end,
      })
      vim.keymap.set("n", "<leader>ch", function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
      end, { desc = "Toggle inlay hints" })

      -- Reopen a file where you left it. Skip commit/rebase buffers, where the
      -- cursor belongs at the top.
      vim.api.nvim_create_autocmd("BufReadPost", {
        desc = "Restore last cursor position",
        callback = function(args)
          local ft = vim.bo[args.buf].filetype
          if ft == "gitcommit" or ft == "gitrebase" then
            return
          end
          local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
          if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(args.buf) then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end,
      })

      -- autoread only reloads on certain events; nudge it on focus/buffer-enter
      -- so files rewritten underneath the editor (Claude edits, git checkout)
      -- refresh without a manual :e.
      vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave", "BufEnter" }, {
        desc = "Reload buffers changed on disk",
        callback = function()
          if vim.bo.buftype == "" and vim.fn.mode() ~= "c" then
            vim.cmd("checktime")
          end
        end,
      })

      -- Spell checking on prose buffers only (markdown/docs, git commit &
      -- rebase messages, plain text). Left off in code so it never flags Nix
      -- attrs or identifiers; `spelloptions=camel` (set in opts) still splits
      -- CamelCase words here. Correct under the cursor with `z=`, add with `zg`.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "markdown", "gitcommit", "gitrebase", "text" },
        desc = "Enable spell check on prose buffers",
        callback = function()
          vim.opt_local.spell = true
        end,
      })

      -- Name the which-key <leader> menus so the popup reads as labelled groups
      -- instead of a flat key list.
      require("which-key").add({
        { "<leader>a", group = "AI / Claude" },
        { "<leader>b", group = "File" },
        { "<leader>c", group = "Code" },
        { "<leader>f", group = "Find" },
        { "<leader>g", group = "Git" },
        { "<leader>q", group = "Session" },
        { "<leader>s", group = "Search / replace" },
        { "<leader>x", group = "Diagnostics" },
      })

      -- Full git UI (stage/commit/branch/rebase) floated over the editor, the
      -- git-workflow companion to the inline gitsigns hunk keymaps. Reuses the
      -- toggleterm runtime already loaded for the bottom terminal panel.
      local lazygit = require("toggleterm.terminal").Terminal:new({
        cmd = "lazygit",
        direction = "float",
        float_opts = { border = "curved" },
        hidden = true,
      })
      vim.keymap.set("n", "<leader>gg", function()
        lazygit:toggle()
      end, { desc = "Lazygit" })

      -- kubeconform: strict Kubernetes manifest conformance, complementing the
      -- schema validation yamlls already does from SchemaStore. nvim-lint ships
      -- no kubeconform linter, so define one; it reads the buffer on stdin and
      -- reports per-resource schema errors. kubeconform emits no line numbers,
      -- so findings land on line 1 with the offending kind/name/path in the
      -- message (still surfaced through Trouble and virtual text like any
      -- diagnostic).
      require("lint").linters.kubeconform = {
        cmd = "kubeconform",
        stdin = true,
        args = { "-strict", "-ignore-missing-schemas", "-output", "json", "-" },
        ignore_exitcode = true, -- non-zero simply means "found problems"
        parser = function(output, _)
          local diags = {}
          local ok, decoded = pcall(vim.json.decode, output)
          if not ok or type(decoded) ~= "table" or type(decoded.resources) ~= "table" then
            return diags
          end
          for _, res in ipairs(decoded.resources) do
            if res.status == "statusInvalid" or res.status == "statusError" then
              local label = string.format(
                "%s/%s",
                (res.kind ~= nil and res.kind ~= "") and res.kind or "?",
                (res.name ~= nil and res.name ~= "") and res.name or "?"
              )
              local errs = res.validationErrors
              if type(errs) == "table" and #errs > 0 then
                for _, e in ipairs(errs) do
                  table.insert(diags, {
                    lnum = 0,
                    col = 0,
                    severity = vim.diagnostic.severity.ERROR,
                    source = "kubeconform",
                    message = string.format("%s: %s %s", label, e.path or "", e.msg or ""),
                  })
                end
              else
                table.insert(diags, {
                  lnum = 0,
                  col = 0,
                  severity = vim.diagnostic.severity.ERROR,
                  source = "kubeconform",
                  message = string.format("%s: %s", label, res.msg or "invalid"),
                })
              end
            end
          end
          return diags
        end,
      }

      -- Run kubeconform ONLY on buffers that actually look like manifests (a
      -- top-level apiVersion + kind). A blanket lintersByFt entry would flag
      -- every non-k8s YAML (docker-compose, CI configs) with "missing 'kind'
      -- key", so gate it here instead. yamllint still runs on all YAML via the
      -- nixvim lint module's own autocmd; this is an additive namespace.
      local function looks_like_manifest(bufnr)
        local has_api, has_kind = false, false
        for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, 512, false)) do
          if l:match("^apiVersion:%s*%S") then
            has_api = true
          end
          if l:match("^kind:%s*%S") then
            has_kind = true
          end
          if has_api and has_kind then
            return true
          end
        end
        return false
      end
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        desc = "kubeconform: validate Kubernetes manifests",
        callback = function(args)
          if
            vim.bo[args.buf].filetype == "yaml"
            and vim.bo[args.buf].buftype == ""
            and looks_like_manifest(args.buf)
          then
            require("lint").try_lint("kubeconform")
          end
        end,
      })

      -- Terminal tab system: <A-t> creates a new horizontal terminal tab,
      -- <A-[> / <A-]> cycle through them in normal mode.
      -- <leader>t toggles whichever terminal is currently active.
      do
        local term_count = 1
        local term_active = 1

        local function term_go(id)
          vim.cmd("ToggleTerm count=" .. id)
          term_active = id
        end

        vim.keymap.set("n", "<leader>t", function()
          term_go(term_active)
        end, { desc = "Toggle terminal" })

        vim.keymap.set({ "n", "t" }, "<A-t>", function()
          term_count = term_count + 1
          term_go(term_count)
        end, { desc = "New terminal tab" })

        vim.keymap.set("n", "<A-[>", function()
          if term_active > 1 then term_go(term_active - 1) end
        end, { desc = "Previous terminal tab" })

        vim.keymap.set("n", "<A-]>", function()
          if term_active < term_count then term_go(term_active + 1) end
        end, { desc = "Next terminal tab" })
      end

      -- flash.nvim jump motions. `s` + two chars labels every visible match and
      -- teleports there (normal/visual/operator-pending). `S` jumps by treesitter
      -- node, but only in normal/operator mode so nvim-surround keeps visual `S`
      -- (add surround around a selection).
      vim.keymap.set({ "n", "x", "o" }, "s", function()
        require("flash").jump()
      end, { desc = "Flash jump" })
      vim.keymap.set({ "n", "o" }, "S", function()
        require("flash").treesitter()
      end, { desc = "Flash treesitter" })

      -- persistence.nvim: auto-restore the session only when Neovim is launched
      -- with no file arguments inside a zellij session — i.e. the `coding`
      -- layout's bare `nvim` in a project dir. Single-file $EDITOR use (git
      -- commit, kubectl edit → argc >= 1) is left untouched, matching the same
      -- "opened on a project" gate the zellij tab-naming autocmd uses. `nested`
      -- lets the restored buffers fire their own LSP/cursor autocmds.
      vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Restore session on bare nvim in a project",
        nested = true,
        callback = function()
          if vim.fn.argc() == 0 and vim.env.ZELLIJ ~= nil then
            require("persistence").load()
          end
        end,
      })
      vim.keymap.set("n", "<leader>qs", function()
        require("persistence").load()
      end, { desc = "Restore session" })
      vim.keymap.set("n", "<leader>qd", function()
        require("persistence").stop()
      end, { desc = "Stop saving session" })
    '';

    # Formatters / linters / kube tooling that must be on Neovim's PATH.
    # (LSP server binaries are added automatically by the server options above.)
    extraPackages =
      with pkgs;
      [
        nixfmt
        prettierd
        stylua
        shfmt
        yamllint
        helm-ls
        kubeconform
        kustomize
        lazygit # full git UI, floated on <leader>gg (see extraConfigLua)
        claude-code # `claude` CLI used by the claudecode.nvim integration
        ripgrep # `rg` backs grug-far's find & replace (and Telescope live_grep)
      ]
      # wl-copy/wl-paste: the fast path for the WSL clipboard bridge only. It is
      # a Linux-only package (it pulls wayland), so every other provider —
      # notably macOS' pbcopy — must not drag it in.
      ++ lib.optionals (clipboardProvider == "wsl") [ wl-clipboard ];

    # VSCode-style keybindings.
    #
    # Terminal caveat: Windows Terminal cannot deliver most Ctrl-Shift-<key>
    # chords to a WSL app (no kitty keyboard protocol), so those are marked
    # "best effort" and each has a reliable F-key or <leader> equivalent.
    keymaps = [
      # -- Command palette / quick open --------------------------------------
      {
        mode = "n";
        key = "<F1>";
        action = "<cmd>Telescope commands<cr>";
        options.desc = "Command palette";
      }
      {
        mode = "n";
        key = "<C-p>";
        action = "<cmd>Telescope find_files<cr>";
        options.desc = "Quick open (files)";
      }

      # -- Claude Code -------------------------------------------------------
      {
        mode = "n";
        key = "<leader>ac";
        action = "<cmd>ClaudeCode<cr>";
        options.desc = "Claude Code (toggle)";
      }
      {
        mode = "n";
        key = "<leader>af";
        action = "<cmd>ClaudeCodeFocus<cr>";
        options.desc = "Claude Code (focus)";
      }
      {
        mode = "v";
        key = "<leader>as";
        action = "<cmd>ClaudeCodeSend<cr>";
        options.desc = "Send selection to Claude";
      }
      {
        mode = "n";
        key = "<leader>ab";
        action.__raw = ''function() vim.cmd("ClaudeCodeAdd " .. vim.fn.expand("%:p")) end'';
        options.desc = "Add current file to Claude context";
      }
      {
        mode = "n";
        key = "<leader>aa";
        action = "<cmd>ClaudeCodeDiffAccept<cr>";
        options.desc = "Accept Claude diff";
      }
      {
        mode = "n";
        key = "<leader>ad";
        action = "<cmd>ClaudeCodeDiffDeny<cr>";
        options.desc = "Deny Claude diff";
      }
      {
        mode = "n";
        key = "<C-S-p>"; # best effort
        action = "<cmd>Telescope commands<cr>";
        options.desc = "Command palette";
      }
      # Project-wide find & replace with edit-in-place (VSCode's Ctrl-Shift-F
      # Search panel). Ctrl-Shift-F cannot be delivered to a WSL app, so the
      # reliable entry points are <leader>sr / <leader>sw. (Quick read-only
      # content search is still Telescope live_grep on <leader>fg.)
      {
        mode = "n";
        key = "<C-S-f>"; # best effort; use <leader>sr instead
        action.__raw = ''function() require("grug-far").open() end'';
        options.desc = "Find & replace in files";
      }
      {
        mode = "n";
        key = "<leader>sr";
        action.__raw = ''function() require("grug-far").open() end'';
        options.desc = "Search & replace (project)";
      }
      {
        mode = "v";
        key = "<leader>sr";
        action.__raw = ''function() require("grug-far").with_visual_selection() end'';
        options.desc = "Search & replace selection (project)";
      }
      {
        mode = "n";
        key = "<leader>sw";
        action.__raw = ''function() require("grug-far").open({ prefills = { search = vim.fn.expand("<cword>") } }) end'';
        options.desc = "Search & replace word under cursor";
      }
      # -- Save / select / clipboard -----------------------------------------
      {
        mode = [
          "n"
          "i"
          "v"
        ];
        key = "<C-s>";
        action = "<Cmd>w<CR>"; # <Cmd> keeps insert/visual mode
        options.desc = "Save file";
      }
      {
        mode = "n";
        key = "<C-a>";
        action = "ggVG";
        options.desc = "Select all";
      }
      {
        mode = "v";
        key = "<C-c>";
        action = "\"+y";
        options.desc = "Copy to system clipboard";
      }
      {
        mode = "v";
        key = "<C-x>";
        action = "\"+d";
        options.desc = "Cut to system clipboard";
      }
      {
        mode = [
          "i"
          "c"
        ];
        key = "<C-v>";
        action = "<C-r>+"; # normal-mode <C-v> stays visual-block
        options.desc = "Paste from system clipboard";
      }

      # -- Comment toggle (Ctrl-/) -------------------------------------------
      {
        mode = "n";
        key = "<C-/>";
        action = "<cmd>lua require('Comment.api').toggle.linewise.current()<cr>";
        options.desc = "Toggle comment";
      }
      {
        mode = "n";
        key = "<C-_>"; # some terminals send Ctrl-/ as Ctrl-_
        action = "<cmd>lua require('Comment.api').toggle.linewise.current()<cr>";
        options.desc = "Toggle comment";
      }
      {
        mode = "v";
        key = "<C-/>";
        action = "<Plug>(comment_toggle_linewise_visual)";
        options = {
          remap = true;
          desc = "Toggle comment";
        };
      }
      {
        mode = "v";
        key = "<C-_>";
        action = "<Plug>(comment_toggle_linewise_visual)";
        options = {
          remap = true;
          desc = "Toggle comment";
        };
      }

      # -- Move / duplicate lines (Alt-Up/Down) ------------------------------
      {
        mode = "n";
        key = "<A-Down>";
        action = "<cmd>m .+1<cr>==";
        options.desc = "Move line down";
      }
      {
        mode = "n";
        key = "<A-Up>";
        action = "<cmd>m .-2<cr>==";
        options.desc = "Move line up";
      }
      {
        mode = "i";
        key = "<A-Down>";
        action = "<esc><cmd>m .+1<cr>==gi";
        options.desc = "Move line down";
      }
      {
        mode = "i";
        key = "<A-Up>";
        action = "<esc><cmd>m .-2<cr>==gi";
        options.desc = "Move line up";
      }
      {
        mode = "v";
        key = "<A-Down>";
        action = ":m '>+1<cr>gv=gv";
        options.desc = "Move selection down";
      }
      {
        mode = "v";
        key = "<A-Up>";
        action = ":m '<-2<cr>gv=gv";
        options.desc = "Move selection up";
      }
      {
        mode = "n";
        key = "<A-S-Down>"; # best effort
        action = "<cmd>t.<cr>";
        options.desc = "Duplicate line down";
      }

      # -- Code navigation (F-keys mirror VSCode) ----------------------------
      {
        mode = "n";
        key = "<F2>";
        action = "<cmd>lua vim.lsp.buf.rename()<cr>";
        options.desc = "Rename symbol";
      }
      {
        mode = "n";
        key = "<F12>";
        action = "<cmd>lua vim.lsp.buf.definition()<cr>";
        options.desc = "Go to definition";
      }
      {
        mode = "n";
        key = "<S-F12>";
        action = "<cmd>Telescope lsp_references<cr>";
        options.desc = "Find references";
      }
      {
        mode = "n";
        key = "<C-.>"; # best effort; also <leader>ca
        action = "<cmd>lua vim.lsp.buf.code_action()<cr>";
        options.desc = "Quick fix / code action";
      }
      {
        mode = "n";
        key = "<F8>";
        action = "<cmd>lua vim.diagnostic.jump({ count = 1, float = true })<cr>";
        options.desc = "Next problem";
      }
      {
        mode = "n";
        key = "<S-F8>";
        action = "<cmd>lua vim.diagnostic.jump({ count = -1, float = true })<cr>";
        options.desc = "Previous problem";
      }
      {
        mode = "n";
        key = "<A-Left>";
        action = "<C-o>";
        options.desc = "Navigate back";
      }
      {
        mode = "n";
        key = "<A-Right>";
        action = "<C-i>";
        options.desc = "Navigate forward";
      }

      # -- Format ------------------------------------------------------------
      {
        mode = "n";
        key = "<A-S-f>"; # best effort; also <leader>cf
        action.__raw = ''function() require("conform").format({ async = true, lsp_format = "fallback" }) end'';
        options.desc = "Format document";
      }
      {
        mode = "n";
        key = "<leader>cf";
        action.__raw = ''function() require("conform").format({ async = true, lsp_format = "fallback" }) end'';
        options.desc = "Format buffer";
      }

      # -- Git: diff & history (diffview) ------------------------------------
      {
        mode = "n";
        key = "<leader>gv";
        action = "<cmd>DiffviewOpen<cr>";
        options.desc = "Diff view (working tree)";
      }
      {
        mode = "n";
        key = "<leader>gV";
        action = "<cmd>DiffviewClose<cr>";
        options.desc = "Close diff view";
      }
      {
        mode = "n";
        key = "<leader>gh";
        action = "<cmd>DiffviewFileHistory %<cr>";
        options.desc = "File history (current file)";
      }
      {
        mode = "n";
        key = "<leader>gH";
        action = "<cmd>DiffviewFileHistory<cr>";
        options.desc = "File history (branch)";
      }

      # -- Code outline (aerial) ---------------------------------------------
      {
        mode = "n";
        key = "<leader>co";
        action = "<cmd>AerialToggle<cr>";
        options.desc = "Code outline (aerial)";
      }

      # -- Markdown ----------------------------------------------------------
      # Flip the current buffer between the rendered document and the raw
      # markdown source (render-markdown.nvim). Handy when editing tables/links
      # where seeing the literal syntax is easier than the rendered form.
      {
        mode = "n";
        key = "<leader>cm";
        action = "<cmd>RenderMarkdown toggle<cr>";
        options.desc = "Toggle markdown render";
      }

      # -- Panels ------------------------------------------------------------
      # <C-b> / <leader>e move focus to the yazi pane on the left (the file
      # manager is a zellij pane now, not an in-editor panel). This is the same
      # hop as <C-h> at the leftmost split; kept under the familiar VSCode keys
      # for discoverability. A no-op outside zellij.
      {
        mode = "n";
        key = "<C-b>";
        action = "<cmd>lua vim.fn.system({ 'zellij', 'action', 'move-focus', 'left' })<cr>";
        options.desc = "Focus file manager (yazi pane)";
      }
      {
        mode = "n";
        key = "<leader>e";
        action = "<cmd>lua vim.fn.system({ 'zellij', 'action', 'move-focus', 'left' })<cr>";
        options.desc = "Focus file manager (yazi pane)";
      }

      {
        mode = "t";
        key = "<Esc>";
        action = "<C-\\><C-n>";
        options.desc = "Terminal: exit to normal mode";
      }
      {
        mode = "n";
        key = "<leader>xx";
        action = "<cmd>Trouble diagnostics toggle<cr>";
        options.desc = "Problems (Trouble)";
      }
      {
        mode = "n";
        key = "<leader>xX";
        action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
        options.desc = "Problems: current buffer";
      }
      {
        mode = "n";
        key = "<leader>xs";
        action = "<cmd>Trouble symbols toggle focus=false<cr>";
        options.desc = "Symbols (Trouble)";
      }
      {
        mode = "n";
        key = "<leader>xr";
        action = "<cmd>Trouble lsp toggle focus=false win.position=right<cr>";
        options.desc = "LSP references/defs (Trouble)";
      }
      {
        mode = "n";
        key = "<leader>xt";
        action = "<cmd>TodoTrouble<cr>";
        options.desc = "TODOs (Trouble)";
      }
      {
        mode = "n";
        key = "<leader>xq";
        action = "<cmd>Trouble qflist toggle<cr>";
        options.desc = "Quickfix list (Trouble)";
      }
      {
        mode = "n";
        key = "<leader>xl";
        action = "<cmd>Trouble loclist toggle<cr>";
        options.desc = "Location list (Trouble)";
      }

      # -- File tabs (Neovim tabline) ----------------------------------------
      # Files are opened as nvim tabs (--remote-tab via yazi/fif); <S-h>/<S-l>
      # navigate tabs and <leader>bd closes the current one.
      {
        mode = "n";
        key = "<S-h>";
        action = "<cmd>tabprev<cr>";
        options.desc = "Previous file tab";
      }
      {
        mode = "n";
        key = "<S-l>";
        action = "<cmd>tabnext<cr>";
        options.desc = "Next file tab";
      }
      {
        mode = "n";
        key = "<C-Tab>"; # best effort
        action = "<cmd>tabnext<cr>";
        options.desc = "Next file tab";
      }
      {
        mode = "n";
        key = "<leader>bd";
        action = "<cmd>q<cr>";
        options.desc = "Close file";
      }
      {
        mode = "n";
        key = "<Esc>";
        action = "<cmd>nohlsearch<cr>";
        options.desc = "Clear search highlight";
      }
    ];
  };
}
