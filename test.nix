{ config, lib, ... }:
{
  sources.disko = builtins.fetchTarball "https://github.com/nix-community/disko/tarball/master";

  modules.disko = import "${config.sources.disko}/module.nix";

  imports = [ ./disko.nix ];
}
