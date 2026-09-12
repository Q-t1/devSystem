# The `coding` IDE: a two-pane zellij workspace — yazi as a file sidebar on the
# left, Neovim (see ./nvim.nix) on the right — bridged by a per-session nvim
# socket so yazi/fif open files as native nvim tabs. Reusable across profiles;
# each profile only sets `programs.codingIde.clipboardProvider` for its host.
{
  pkgs,
  lib,
  config,
  ...
}:

let
  # Catppuccin Mocha (mauve accent) for yazi — matches the Neovim IDE's
  # colorscheme (nvim.nix) and the zellij chrome, so editor, picker and
  # multiplexer share one palette. Catppuccin ships a plain per-accent theme.toml
  # (not the yazi flavor-package format), so read it straight into
  # programs.yazi.theme; swap the filename for another accent under themes/mocha/.
  catppuccinYaziTheme = builtins.fromTOML (
    builtins.readFile "${
      pkgs.fetchFromGitHub {
        owner = "catppuccin";
        repo = "yazi";
        rev = "d62802be39210ea10e54b3e3b09735c6cb9e57c1";
        hash = "sha256-bwzEO8exoBwa19q+jnYjHkaamGl2mhfukIEhDfUCRGI=";
      }
    }/themes/mocha/catppuccin-mocha-mauve.toml"
  );

  nvimBin = "${config.programs.nixvim.build.package}/bin/nvim";
  zellijBin = "${pkgs.zellij}/bin/zellij";
  lazygitBin = "${pkgs.lazygit}/bin/lazygit";

  # Starts Neovim listening on a session-scoped socket so yazi, fif, and
  # any other pane in the same zellij session can open files into the same
  # instance via --remote-tab, giving a native nvim tabline instead of
  # zellij stacked panes.
  codingNvim = pkgs.writeShellScript "coding-nvim" ''
    sock="/tmp/nvim-$ZELLIJ_SESSION_NAME.sock"
    exec ${nvimBin} --listen "$sock" "$@"
  '';

  # Opens $1 in the session's Neovim via its socket (--remote-tab creates a
  # new nvim tab), then focuses the editor pane. Called from yazi (left pane);
  # move-focus Right always lands on the editor column.
  openFileInNvim = pkgs.writeShellScript "open-file-in-nvim" ''
    file=$(${pkgs.coreutils}/bin/realpath -- "$1")
    sock="/tmp/nvim-$ZELLIJ_SESSION_NAME.sock"
    ${nvimBin} --server "$sock" --remote-tab "$file"
    ${zellijBin} action move-focus Right
  '';

  # yazi's built-in `S`/`s` search only ever surfaces files (never a matched
  # line) and its results don't route through the `edit` opener reliably. These
  # replace both with fzf pickers — the same flow as the `fif` shell function —
  # that open the pick in the session's Neovim over the socket and (for content
  # search) jump to the matched line, then focus the editor pane on the right.
  #
  # Launched from yazi via `shell "<script>" --block`, so fzf takes over the
  # yazi (left) pane while running; on pick we hop focus Right to the editor.
  yaziRgSearch = pkgs.writeShellScript "yazi-rg-search" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.ripgrep
        pkgs.fzf
        pkgs.bat
        pkgs.coreutils
        pkgs.gnused
      ]
    }:$PATH
    RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case"
    result=$(
      : | fzf --ansi --disabled \
          --bind "start:reload:$RG_PREFIX {q} || true" \
          --bind "change:reload:sleep 0.1; $RG_PREFIX {q} || true" \
          --delimiter ':' \
          --preview 'bat --color=always --highlight-line {2} -- {1}' \
          --preview-window 'right:60%,+{2}+3/3,border-left'
    ) || exit 0
    [ -z "$result" ] && exit 0
    clean=$(printf '%s' "$result" | sed -E 's/\x1b\[[0-9;]*[mGKHF]//g')
    file=''${clean%%:*}
    rest=''${clean#*:}
    line=''${rest%%:*}
    [ -z "$file" ] && exit 0
    abs=$(realpath -- "$file")
    sock="/tmp/nvim-$ZELLIJ_SESSION_NAME.sock"
    if [ -S "$sock" ]; then
      ${nvimBin} --server "$sock" --remote-tab "$abs"
      ${nvimBin} --server "$sock" --remote-send "<Esc>:''${line}<CR>"
      ${zellijBin} action move-focus Right
    else
      ${nvimBin} "$abs" "+$line"
    fi
  '';
  yaziFdSearch = pkgs.writeShellScript "yazi-fd-search" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.fd
        pkgs.fzf
        pkgs.bat
        pkgs.coreutils
      ]
    }:$PATH
    file=$(
      fd --type f --hidden --follow --exclude .git |
        fzf --ansi \
            --preview 'bat --color=always -- {}' \
            --preview-window 'right:60%,border-left'
    ) || exit 0
    [ -z "$file" ] && exit 0
    abs=$(realpath -- "$file")
    sock="/tmp/nvim-$ZELLIJ_SESSION_NAME.sock"
    if [ -S "$sock" ]; then
      ${nvimBin} --server "$sock" --remote-tab "$abs"
      ${zellijBin} action move-focus Right
    else
      ${nvimBin} "$abs"
    fi
  '';

  # Shared zellij chrome for both IDE layouts (coding + git): the built-in
  # tab-bar on top, and a zjstatus strip on the bottom showing the session
  # name (left) and the git branch + clock (right). The branch command appends
  # a " *" when the tree is dirty (tracked changes or untracked files), so the
  # status bar doubles as a "you have uncommitted work" indicator. Factored out
  # here so the two layouts stay identical instead of drifting.
  zellijChrome = ''
    pane size=1 borderless=true {
        plugin location="zellij:tab-bar"
    }
    children
    pane size=1 borderless=true {
        plugin location="file:${pkgs.zellijPlugins.zjstatus}" {
            format_left   "#[fg=#cba6f7,bold] {session} "
            format_center ""
            format_right  "{command_git_branch}{datetime}"

            command_git_branch {
                command  "bash"
                args     "-c" "b=$(git -C #{cwd} branch --show-current 2>/dev/null) || exit 0; [ -z \"$b\" ] && exit 0; [ -n \"$(git -C #{cwd} status --porcelain 2>/dev/null)\" ] && b=\"$b *\"; printf %s \"$b\""
                format   "#[fg=#a6e3a1]  {stdout} "
                interval "5"
            }

            datetime {
                format   "#[fg=#6c7086,italic] %H:%M "
                timezone "Europe/Paris"
            }
        }
    }
  '';
in
{
  imports = [ ./nvim.nix ];

  options.programs.codingIde.clipboardProvider = lib.mkOption {
    type = lib.types.enum [
      "wsl"
      "pbcopy"
      "osc52"
      "none"
    ];
    default = "osc52";
    example = "wsl";
    description = ''
      How the IDE's Neovim and zellij reach the system clipboard.
      "wsl" bridges to Windows via wl-copy with a clip.exe/PowerShell fallback
      (WSLg); "pbcopy" uses macOS' native pbcopy/pbpaste; "osc52" uses terminal
      OSC 52 escapes, which work headless / over SSH (e.g. a remote container);
      "none" leaves Neovim's autodetection be.
    '';
  };

  config = {
    # IDE tooling the launcher and shell functions call interactively. bat and
    # fzf come from the shared base (config/common/home.nix); the packaged
    # helper scripts above carry their own deps via makeBinPath.
    home.packages = with pkgs; [
      fd # yazi's file finder + `s` name search (the `coding` left pane)
      ripgrep # yazi's content search and the `fif` function
      lazygit # full git UI; also the `git` zellij layout / gitview
      # `claude` on the interactive shell's PATH. nvim.nix lists it too, but
      # that only reaches the wrapped Neovim (claudecode.nvim), not the shell.
      claude-code
    ];

    # Free Ctrl-S / Ctrl-Q from XON/XOFF flow control so the save keybind never
    # freezes an interactive terminal, and provide the `coding` launcher.
    programs.zsh.initContent = ''
        [[ $- == *i* ]] && stty -ixon 2>/dev/null

        # `coding [target]` opens the IDE inside a zellij "coding" layout (yazi file
        # pane on the left, Neovim + a shell strip on the right), rooted at the target
        # so yazi, the LSP and telescope all use that project. A file target skips the
        # layout and just edits the file (keeps single-file / $EDITOR-style use fast).
        # Inside an existing zellij session it adds a tab instead of nesting.
        coding() {
          local target="''${1:-.}"
          if [[ -f "$target" ]]; then
            nvim -- "$target"
            return
          fi
          local dir="''${target:A}" # zsh: resolve to an absolute path
          local tab_name="coding: ''${dir:t}"
          if [[ -n "$ZELLIJ" ]]; then
            zellij action new-tab --layout coding --cwd "$dir" --name "$tab_name"
          else
            local session_name="coding-''${dir:t}"
            local _sessions
            _sessions=$(zellij list-sessions 2>/dev/null)
            # A live session has the name but no EXITED marker; an exited one shows
            # "(EXITED - attach to resurrect)" — attaching resurrects it as a bare
            # shell without the layout, which is the "run twice" bug. Delete the
            # zombie and start fresh instead.
            local _live
            _live=$(echo "$_sessions" | grep -F "$session_name" | grep -vi 'EXITED')
            if [[ -n "$_live" ]]; then
              ( builtin cd -- "$dir" && zellij attach "$session_name" )
            else
              zellij delete-session "$session_name" 2>/dev/null
              # Use -n/--new-session-with-layout, NOT --layout: with -s present,
              # `--layout coding` means "add a tab to session coding-<dir>", which
              # doesn't exist yet, so zellij errors "Session not found". -n always
              # starts a new session, so it composes with -s.
              ( builtin cd -- "$dir" && zellij -s "$session_name" -n coding )
            fi
          fi
        }

      # `gitview [dir]` opens a dedicated git tab (full-screen lazygit). Inside
      # an existing zellij session it adds a tab; outside it starts a new session.
      gitview() {
        local target="''${1:-.}"
        local dir="''${target:A}"
        local tab_name="git: ''${dir:t}"
        if [[ -n "$ZELLIJ" ]]; then
          zellij action new-tab --layout git --cwd "$dir" --name "$tab_name"
        else
          ( builtin cd -- "$dir" && zellij -n git )
        fi
      }

      # `fif <pattern> [rg-args]` — interactive ripgrep | fzf content search with
      # bat preview. Selecting a match opens the file at the matched line in the
      # session's Neovim via its socket, then moves focus to the editor pane.
      fif() {
        if [[ $# -eq 0 ]]; then
          print -u2 "usage: fif <pattern> [rg-args...]"; return 1
        fi
        local result
        result=$(
          rg --color=always --line-number --no-heading --smart-case -- "$@" |
            fzf --ansi \
                --delimiter ':' \
                --preview 'bat --color=always --highlight-line {2} -- {1}' \
                --preview-window 'right:60%,+{2}+3/3,border-left'
        ) || return
        local clean file rest line abs sock
        clean=$(printf '%s' "$result" | sed 's/\x1b\[[0-9;]*[mGKHF]//g')
        file="''${clean%%:*}"
        rest="''${clean#*:}"
        line="''${rest%%:*}"
        abs=$(realpath -- "$file")
        sock="/tmp/nvim-''${ZELLIJ_SESSION_NAME}.sock"
        if [[ -S "''${sock}" ]]; then
          ${zellijBin} action move-focus Up
          ${nvimBin} --server "''${sock}" --remote-tab "''${abs}"
          ${nvimBin} --server "''${sock}" --remote-send "<Esc>:''${line}<CR>"
        else
          nvim "''${abs}" "+''${line}"
        fi
      }
    '';

    # yazi is the IDE's file manager, running as the persistent left pane of the
    # `coding` zellij layout (below). Picking a file opens it in the Neovim pane on
    # the right over a server socket (see the `edit` opener and the layout).
    programs.yazi = {
      enable = true;

      # No shell wrapper: yazi is the IDE's file pane, not a `y`-to-cd shell
      # command, so the zsh integration would only add noise.
      enableZshIntegration = false;

      settings = {
        mgr = {
          # Collapse yazi to a single column (parent + preview off). In a narrow
          # sidebar this reads like a file tree, and the content preview is
          # redundant anyway — the file's contents show in the Neovim pane.
          ratio = [
            0
            1
            0
          ];
          show_hidden = true; # dotfiles matter in a Nix repo (.rtk, .git-ignored…)
          sort_dir_first = true;
        };

        # Open (Enter) sends the picked file to the session's Neovim via its
        # socket (--remote-tab), which opens it as a new nvim tab. block=false
        # keeps yazi visible as the sidebar. realpath is required: yazi may pass
        # a path relative to its cwd, but the socket command resolves against
        # nvim's cwd → wrong file from a subdir without it.
        opener.edit = [
          {
            run = "${openFileInNvim} \"$1\"";
            desc = "Open in editor";
            block = false;
          }
        ];
        open.prepend_rules = [
          {
            url = "*";
            use = "edit";
          }
        ];
      };

      # Replace yazi's built-in fd/rg search (which can't open at a matched line
      # and doesn't route content-search results through the `edit` opener) with
      # fzf pickers that open the pick in the session's Neovim — the rg one jumps
      # to the matched line. prepend_keymap wins over the defaults, so `s`/`S`
      # keep their familiar meaning. Run with --block so fzf owns the pane while
      # picking (see yaziRgSearch / yaziFdSearch in the let block above).
      keymap.mgr.prepend_keymap = [
        {
          on = "S";
          run = ''shell "${yaziRgSearch}" --block'';
          desc = "Search file contents (rg) → open at match";
        }
        {
          on = "s";
          run = ''shell "${yaziFdSearch}" --block'';
          desc = "Search files by name (fd) → open";
        }
      ];

      # Catppuccin Mocha (mauve) — see the let binding at the top of this file.
      theme = catppuccinYaziTheme;
    };

    programs.zellij = {
      enable = true;

      settings = {
        # Catppuccin Mocha — a zellij built-in theme, matched to the Neovim IDE's
        # colorscheme (nvim.nix) so the editor and the surrounding zellij chrome
        # share one palette.
        theme = "catppuccin-mocha";

        # Mouse drag-select in a (non-Neovim) pane copies straight to the system
        # clipboard. On WSL that routes through clip.exe and on macOS through
        # pbcopy (copy_command below); elsewhere zellij falls back to OSC 52.
        # Neovim panes keep their own mouse handling (mouse=a), since Neovim
        # requests mouse tracking and zellij forwards events to it.
        mouse_mode = true;
        copy_on_select = true;
      }
      // lib.optionalAttrs (config.programs.codingIde.clipboardProvider == "wsl") {
        # WSL: bypass OSC 52 and hand the selection to Windows directly —
        # reliable regardless of WSLg's Wayland state.
        copy_command = "clip.exe";
      }
      // lib.optionalAttrs (config.programs.codingIde.clipboardProvider == "pbcopy") {
        # macOS: the real system clipboard, no terminal round-trip needed.
        copy_command = "pbcopy";
      };

      # Full-screen lazygit tab, launched by `gitview`. Alt-t still adds a
      # terminal below if needed; lazygit's own bottom panel handles most shell
      # needs (press `e` to open the embedded shell in a lazygit split).
      layouts.git = ''
        layout {
            default_tab_template {
                ${zellijChrome}
            }
            tab name="git" focus=true {
                pane name="lazygit" focus=true {
                    command "${lazygitBin}"
                }
            }
        }
      '';

      # IDE workspace launched by the `coding` shell function:
      #
      #   ┌ files ┐┌──────── editor (nvim) ────────┐
      #   │ yazi  ││ [file1] │ [file2] │ [file3] … │  ← nvim tabline (top)
      #   │       │├────────── terminal ───────────┤
      #   └───────┘└───────────────────────────────┘
      #
      # Neovim runs with --listen on a session-scoped socket (coding-nvim wrapper).
      # Enter on a file in yazi calls open-file-in-nvim which does --remote-tab,
      # opening the file as a new nvim tab. The nvim tabline at the top of the
      # editor pane is the open-files list. Alt-t adds a new zellij terminal tab.
      layouts.coding = ''
        layout {
            default_tab_template {
                ${zellijChrome}
            }
            tab name="code" focus=true {
                pane split_direction="vertical" {
                    pane size="24%" name="files" focus=true {
                        command "${config.programs.yazi.finalPackage}/bin/yazi"
                    }
                    pane split_direction="horizontal" {
                        pane size="80%" name="editor" {
                            command "${codingNvim}"
                        }
                        pane stacked=true {
                            pane name="terminal"
                        }
                    }
                }
            }
        }
      '';

      # zellij is modal and, in its Normal mode, intercepts a handful of Ctrl
      # chords before the running app sees them — several of which the nixvim IDE
      # (nvim.nix) relies on, most importantly Ctrl-s (save). Free those in Normal
      # mode so they reach Neovim:
      #   Ctrl-s save · Ctrl-p quick-open / blink prev · Ctrl-n blink next ·
      #   Ctrl-h seamless split/pane nav across Neovim and zellij (see nvim.nix)
      # zellij keeps everything else, driven from its Alt bindings (Alt-n new
      # pane, Alt-h/j/k/l move focus, Alt-+/- resize, Alt-f float, Alt-[/] cycle
      # layouts) plus Ctrl-g lock, Ctrl-t tab, Ctrl-o session, Ctrl-q quit.
      #
      # Alt-t opens a new plain terminal tab (a zellij tab, not a stacked pane).
      extraConfig = ''
        keybinds {
            normal {
                unbind "Ctrl s"
                unbind "Ctrl p"
                unbind "Ctrl n"
                unbind "Ctrl h"

                // Add a new pane to the terminal stack (shows as a horizontal tab strip).
                // Focus must land on the stack first; NewPane without stacked=true
                // adds to the focused stack rather than creating an independent pane.
                bind "Alt t" { MoveFocus "Right"; MoveFocus "Down"; NewPane; }
                bind "Alt q" { CloseTab; }
            }
        }
      '';
    };
  };
}
