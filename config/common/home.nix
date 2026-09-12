{ pkgs, lib, ... }:

{
  programs.nh.enable = true;

  programs.home-manager.enable = true;
  home.packages =
    with pkgs;
    [
      nil
      nixd
      package-version-server
      cachix

      curl
      wget
    ]
    # Ghostty's terminfo entry, so `TERM=xterm-ghostty` resolves on hosts we
    # SSH into from Ghostty. nixpkgs only builds ghostty on Linux; on darwin the
    # Ghostty.app install already ships its own terminfo, so skip it there.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ghostty.terminfo ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # Pin the ZLE keymap to emacs. zsh otherwise auto-selects vi keybindings
    # whenever $EDITOR/$VISUAL contains the substring "vi" — and "nvim" matches,
    # so the wsl profile's `defaultEditor = true` (EDITOR=nvim) silently flipped
    # the shell into vi-mode, where Ctrl-R is `redisplay` instead of
    # history-incremental-search-backward. Setting this makes the keymap
    # deterministic on every host regardless of $EDITOR.
    defaultKeymap = "emacs";

    autocd = true;

    history = {
      size = 100000;
      save = 100000;
      extended = true;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };

    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      # ls family routed through eza (below): grouped dirs, icons, git status.
      ls = "eza --group-directories-first --icons=auto";
      ll = "eza -lah --group-directories-first --icons=auto --git";
      la = "eza -a --group-directories-first --icons=auto";
      lt = "eza --tree --level=2 --group-directories-first --icons=auto";
      cat = "bat";
      gs = "git status";
      gd = "git diff";
      gl = "git log --oneline --graph --decorate";
    };
  };

  # eza — a modern `ls` with icons, git integration and tree view. Aliased into
  # the ls family above so every profile gets it interactively.
  programs.eza = {
    enable = true;
    git = true;
    icons = "auto";
  };

  # bat — a `cat` clone with syntax highlighting and paging. Catppuccin Mocha
  # keeps it in the same palette as fzf/starship (and the wsl IDE).
  programs.bat = {
    enable = true;
    config.theme = "Catppuccin Mocha";
    themes."Catppuccin Mocha" = {
      src = pkgs.fetchFromGitHub {
        owner = "catppuccin";
        repo = "bat";
        rev = "699f60fc8ec434574ca7451b444b880430319941";
        hash = "sha256-6fWoCH90IGumAMc4buLRWL0N61op+AuMNN9CAR9/OdI=";
      };
      file = "themes/Catppuccin Mocha.tmTheme";
    };
  };

  # fzf — fuzzy finder wired into zsh (Ctrl-R history, Ctrl-T files, Alt-C cd).
  # Colors are Catppuccin Mocha so the picker matches the rest of the shell.
  programs.fzf = {
    enable = true;
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
    ];
    colors = {
      "bg+" = "#313244";
      "bg" = "#1e1e2e";
      "spinner" = "#f5e0dc";
      "hl" = "#f38ba8";
      "fg" = "#cdd6f4";
      "header" = "#f38ba8";
      "info" = "#cba6f7";
      "pointer" = "#f5e0dc";
      "marker" = "#b4befe";
      "fg+" = "#cdd6f4";
      "prompt" = "#cba6f7";
      "hl+" = "#f38ba8";
    };
  };

  # zoxide — a smarter `cd` that learns your most-used directories (`z <query>`,
  # `zi` for interactive fzf selection).
  programs.zoxide.enable = true;

  # Starship — fast, pretty cross-shell prompt shared by every profile.
  # zsh integration is enabled by default; it hooks itself into the shell.
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;

      format = lib.concatStrings [
        "$directory"
        "$git_branch"
        "$git_status"
        "$nix_shell"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
        vimcmd_symbol = "[❮](bold yellow)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
        read_only = " ";
      };

      git_branch = {
        symbol = " ";
        style = "bold purple";
      };

      git_status = {
        style = "bold yellow";
      };

      nix_shell = {
        symbol = " ";
        format = "[$symbol$name]($style) ";
        style = "bold blue";
      };

      cmd_duration = {
        min_time = 2000;
        format = "[ $duration]($style) ";
        style = "italic yellow";
      };
    };
  };

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Quentin R.";
        email = "quentin.roccia@gmail.com";
      };
      core.autocrlf = "input";
      core.eol = "lf";
      push.autoSetupRemote = true;
      push.default = "current";
      init.defaultBranch = "main";
    };
  };

  programs.neovim = {
    enable = true;

    withPython3 = false;
    withRuby = false;

    vimAlias = true;
    viAlias = true;
  };

  programs.zed-editor.installRemoteServer = {
    enable = true;
    extensions = [ "nix" ];
  };
}
