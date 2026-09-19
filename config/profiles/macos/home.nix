{ pkgs, lib, ... }:

{
  # The `coding` IDE (yazi + zellij + nixvim). Unlike the container/WSL
  # profiles this one runs natively on macOS, so the clipboard goes straight to
  # pbcopy/pbpaste instead of OSC 52 escapes or the Windows bridge.
  imports = [ ../../modules/coding-ide.nix ];

  programs.codingIde.clipboardProvider = "pbcopy";

  # Migrated off Homebrew — nix is the source of truth for CLI tooling on this
  # machine now. `neovim` came across as the IDE's nixvim (coding-ide), `claude`
  # as the claude-code overlay, and the `pure` prompt was dropped for starship.
  # Homebrew itself stays installed: it still carries `rtk` (a custom tap with
  # no nixpkgs equivalent) and the GUI casks.
  home.packages = with pkgs; [
    nodejs_26
    p7zip
    uv
  ];

  # git-lfs via the Home Manager module rather than a bare package, so the
  # filter/diff/merge clauses it needs land in the Home-Manager-owned
  # ~/.gitconfig. A plain package would install the binary but leave LFS
  # unregistered with git.
  programs.git.lfs.enable = true;

  # Ghostty — the app itself stays a Homebrew cask (nixpkgs only builds ghostty
  # on Linux), so Home Manager only writes ~/.config/ghostty/config. Catppuccin
  # Mocha is one of Ghostty's bundled themes and matches the palette used by
  # bat/fzf (config/common/home.nix) and the coding IDE.
  programs.ghostty = {
    enable = true;
    package = null;
    settings.theme = "Catppuccin Mocha";
  };

  # pipx drops user-installed CLI entry points here.
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Everything below is carried over from the hand-written dotfiles that Home
  # Manager now owns (~/.zshenv, ~/.zprofile, ~/.zshrc — kept as *.backup from
  # the first switch). Each integration is guarded by an existence test so the
  # profile still evaluates and activates on a machine where that tool is gone.
  programs.zsh = {
    # ~/.zshenv — the rust toolchain. Belongs in zshenv rather than zshrc so
    # non-interactive shells (and the IDE's LSPs) see cargo too.
    envExtra = ''
      [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    '';

    # ~/.zprofile — login-shell setup.
    profileExtra = ''
      # Homebrew: PATH/MANPATH/INFOPATH/FPATH for the /opt/homebrew prefix.
      [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

      # Put the nix profile back in front. Home Manager exports PATH from
      # ~/.zshenv, which zsh sources *before* ~/.zprofile, so the brew shellenv
      # above would otherwise shadow every nix-provided tool that Homebrew also
      # ships — most importantly `claude`, whose whole reason for being pinned
      # through config/modules/claude-code.nix is that we choose its version.
      export PATH="$HOME/.nix-profile/bin:$PATH"
    '';

    # ~/.zshrc — interactive bits. The `pure` prompt this used to load is gone;
    # starship (config/common/home.nix) is the prompt on every profile.
    initContent = lib.mkMerge [
      # Homebrew's completion functions have to join fpath before Home Manager
      # runs compinit, hence mkBefore.
      (lib.mkBefore ''
        [ -d /opt/homebrew/share/zsh/site-functions ] && fpath+=("/opt/homebrew/share/zsh/site-functions")
      '')
      ''
        # Unity CLI
        [ -f "$HOME/.unity/env" ] && . "$HOME/.unity/env"
      ''
    ];
  };
}
