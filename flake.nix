{
  description = "Qt1 Home Manager config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # `claude` CLI, replacing the nixpkgs package (see
    # config/modules/claude-code.nix). Deliberately not following our nixpkgs:
    # a different nixpkgs changes the store path and loses the upstream cachix
    # cache hits.
    claude-code.url = "github:sadjow/claude-code-nix";
    # Everything infrastructure: the microVM host layer, its guests and the
    # services on them. This flake only consumes its `nixosModules`; the
    # `microvm` input lives over there. `follows` keeps one nixpkgs per host,
    # so the guests are built from the same revision as their host.
    qt1-infrastructure = {
      # A relative `path:` input cannot be used here — it would resolve inside
      # this flake's store copy. To iterate on a local checkout, pass
      #   --override-input qt1-infrastructure path:/Users/quentin/Projects/Qt1-Infrastructure
      url = "github:Q-t1/Qt1-Infrastructure";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      flake-utils,
      ...
    }:
    let
      lib = nixpkgs.lib;
      # Default account name, used by every profile that doesn't set its own
      # `username` in host.nix (see macos/host.nix for an override example).
      username = "qt1";
      stateVersion = "26.05";

      profilesDir = ./config/profiles;

      hosts = lib.mapAttrs (
        name: _:
        let
          hostCfg = import "${profilesDir}/${name}/host.nix";
          hostUsername = hostCfg.username or username;
          # macOS puts accounts under /Users, Linux under /home. A host.nix may
          # still pin `homeDirectory` explicitly to override this.
          isDarwin = lib.hasSuffix "-darwin" hostCfg.system;
        in
        hostCfg
        // {
          profile = name;
          username = hostUsername;
          homeDirectory =
            hostCfg.homeDirectory or (if isDarwin then "/Users/${hostUsername}" else "/home/${hostUsername}");
        }
      ) (lib.filterAttrs (_: type: type == "directory") (builtins.readDir profilesDir));

      mkHmModule = host: {
        imports = [
          ./config/common/home.nix
          ./config/profiles/${host.profile}/home.nix
        ];
        home = {
          inherit stateVersion;
          username = host.username;
          homeDirectory = host.homeDirectory;
        };
        programs.home-manager.enable = true;
      };

      mkHome =
        _: host:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit (host) system;
            overlays = [ inputs.claude-code.overlays.default ];
            # claude-code is unfree, as it is for the nixos profiles.
            config.allowUnfree = true;
          };
          extraSpecialArgs = {
            inherit inputs;
            inherit (host)
              profile
              system
              username
              kind
              ;
          };
          modules = [ (mkHmModule host) ];
        };

      mkNixos =
        _: host:
        lib.nixosSystem {
          system = host.system;
          specialArgs = {
            inherit inputs;
            inherit (host)
              profile
              system
              username
              kind
              ;
          };

          modules = [
            # Determinate Nix on every NixOS host. This sets `nix.package` to
            # the `determinate` input's build (not nixpkgs'), which lives in
            # https://install.determinate.systems rather than cache.nixos.org.
            # Keep the input current — that cache only holds the current stable
            # build, and a stale pin means compiling Nix from source. See the
            # README for the one-off substituter flags a host's first switch
            # needs, before determinate-nixd manages /etc/nix/nix.conf itself.
            inputs.determinate.nixosModules.default
            ./config/modules/nix-settings.nix
            ./config/modules/claude-code.nix
            ./config/profiles/${host.profile}/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit (host)
                  profile
                  system
                  username
                  kind
                  ;
              };
              home-manager.users.${host.username} = mkHmModule host;
            }
          ]
          ++ lib.optionals (host.kind == "nixos" && host.profile == "wsl") [
            inputs.nixos-wsl.nixosModules.wsl
          ];
        };

      homeHosts = lib.filterAttrs (_: host: host.kind == "home") hosts;

      allNixosHosts = lib.filterAttrs (_: host: host.kind == "nixos") hosts;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    flake-utils.lib.eachSystem systems (system: {
      formatter = nixpkgs.legacyPackages.${system}.nixfmt;
    })
    // {
      homeConfigurations = lib.mapAttrs mkHome homeHosts;
      nixosConfigurations = lib.mapAttrs mkNixos allNixosHosts;
    };
}
