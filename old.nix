let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-22.11";
  pkgs = import nixpkgs { config = { }; overlays = [ ]; };
  lib = pkgs.lib;
  nixos = modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" ({
      system = builtins.currentSystem;
      inherit modules lib;
    });
in
nixos [{
  imports = [
    ("${builtins.fetchTarball "https://github.com/nix-community/disko/tarball/master"}/module.nix")
    ./disko.nix
  ];
}]
