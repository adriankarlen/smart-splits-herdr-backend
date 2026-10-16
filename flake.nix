{
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      neovim-nightly-overlay,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        nightlyPkgs = import nixpkgs {
          inherit system;
          overlays = [
            # The overlay's CI pushes `checks` (not `packages`) to nix-community.cachix.org.
            (_: _: { neovim-unwrapped = neovim-nightly-overlay.checks.${system}.neovim; })
          ];
        };
        treefmt-eval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        treefmt-wrapper = treefmt-eval.config.build.wrapper;
        packagesFor =
          p: with p; [
            actionlint
            emmylua-check
            git
            # the integration suite drives a real server in a private session
            herdr
            jq
            just
            lua51Packages.busted
            lua51Packages.nlua
            neovim
            nixfmt
            prettier
            selene
            shellcheck
            shfmt
            statix
            stylua
            tombi
            treefmt-wrapper
            yamlfmt
          ];
      in
      {
        formatter = treefmt-wrapper;
        devShells = {
          default = pkgs.mkShell {
            name = "backend-herdr";
            packages = packagesFor pkgs;
          };
          ci = pkgs.mkShell {
            name = "ci";
            packages = packagesFor pkgs;
          };
          ci-nightly = nightlyPkgs.mkShell {
            name = "ci-nightly";
            packages = packagesFor nightlyPkgs;
          };
        };
        checks = {
          formatting = treefmt-eval.config.build.check self;
        };
      }
    );
}
