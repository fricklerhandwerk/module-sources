let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-24.11";
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
  lib = pkgs.lib;
  nixos =
    modules:
    import "${nixpkgs}/nixos/lib/eval-config.nix" ({
      system = builtins.currentSystem;
      inherit modules lib;
      specialArgs = {
        # the disadvantage of this pattern is that the `sources` argument is
        # strictly required, otherwise argument resolution will recurse
        # infinitely searching for the corresponding `_module.args`
        sources = { };
      };
    });
in
nixos [
  (
    {
      config,
      lib,
      sources,
      ...
    }:
    let
      disko =
        sources.disko or (builtins.fetchTarball "https://github.com/nix-community/disko/tarball/master");
    in
    {
      imports = [
        ./disko.nix
        "${disko}/module.nix"
      ];
    }
  )
]
