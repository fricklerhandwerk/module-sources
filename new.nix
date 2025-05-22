{ config, lib, ... }:
# the advantage here is that we can resolve conflicts at the call site with `lib.mkForce`
{
  # TODO: we better have abstract source specifications, because `fetchTarball`
  # downloads at evaluation time, and will make broken references let everything fall apart
  sources.disko = builtins.fetchTarball "https://github.com/nix-community/disko/tarball/master";

  modules.disko = "${config.sources.disko}/false.nix";

  imports = [ ./disko.nix ];
}
