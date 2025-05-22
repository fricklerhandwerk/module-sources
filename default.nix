let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-24.11";
  pkgs = import nixpkgs { config = { }; overlays = [ ]; };
  lib = pkgs.lib;
  phased-evaluation = module:
    let
      # 1. collect source declarations and convert them to lock file entries
      # 2. collect module declarations and convert them to `imports` based on sources fetched from the lock file
      sources = collectSources module;
      # 3. evaluate regular NixOS modules; pass imports obtained in step 2
      config = nixos ([ module ] ++ sources.config.imports);
    in
    config;
  # TODO: this could also take a lock file.
  # if the evaluation result differs from the lock file, it could throw an error.
  # the error can suggest a command for remediation.
  # for example, one could re-fetch and update the lock file.
  # wrapper tooling can offer an option to run that command automatically and then continue.
  # TODO: make a wrapper tool that only produces a lock file.
  # TODO: make (or re-use) a wrapper tool that fetches from locked references.
  # TODO: if wrapper tooling can pick up from here, there will be additional failure modes.
  collectSources = module:
    lib.evalModules {
      modules = [
        module
        ./sources.nix
        # ignore all other definitions
        { _module.check = false; }
      ];
    };
  nixos = modules:
    import "${nixpkgs}/nixos/lib/eval-config.nix" ({
      system = builtins.currentSystem;
      inherit modules lib;
    });
in
rec {
  inherit phased-evaluation;
  # moral equality is tedious to check, because it needs careful filtering:
  # - two functions are never equal
  # - many attribute values have failing assertions
  new = (phased-evaluation ./new.nix).config.fileSystems;
  next = (import ./next.nix).config.fileSystems;
  old = (import ./old.nix).config.fileSystems;
  # TODO: this needs proper tests.
  test = new == next && new == old;
}
