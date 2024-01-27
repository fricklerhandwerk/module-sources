# Module-level source references

This is an attempt to create a Nixpkgs module which allows declaring remote source references at the module level.

## Problem

When setting option values on modules that are not shipped with NixOS, without context it's not clear how to ensure that the required modules are actually present.

Example: Disk layouts using [disko](https://github.com/nix-community/disko)

In a NixOS configuration, one could have a file that declares a disk layout:

```nix
# disko.nix
{ ... }:
{
  disko.devices.disk.main = {
    device = "/dev/sda";
    content = {
      type = "gpt";
        root = {
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
```

At this point it's not evident that the `disko` option is not part of NixOS.
Using this module standalone in a different configuration won't work without that contextual knowledge.
This situation negates a central value proposition of the module system!

For a valid NixOS configuration, an `imports` attribute that adds the respective module to the evaluation is required.
It doesn't really matter where this is declared, but to keep the configuration truly modular it should ideally be in the same file as where the option values are set.
This won't work when one wants to use option values set by foreign modules in some other place, but that other place could then also explicitly import the foreign module to make clear that there's a dependency.
Usually none of this is done though, and instead all additional modules are added to the top-level invocation of `evalModules` (via `pkgs.nixos`, or `nixosSystem` with flakes) that one has to maintain in an ever-growing file that tends to be quite massive to begin with.

The disko documentation shows [this clumsy approach](https://github.com/nix-community/disko/blob/2890a8c922a329468e0fa8cab88b83a87240ff24/docs/quickstart.md#L172-L177):

```nix
{ ... }:
{
  imports = [
    "${builtins.fetchTarball "https://github.com/nix-community/disko/tarball/master"}/module.nix"
  ]

  # ...
}
```

Using `fetchTarball` like that is impure though, and therefore won't age well.
Alas, specifying the remote source in a more sophisticated manner, for example using `pkgs.fetchFromGitHub` with a pinned revision, immediately exposes a long-standing, major user experience issue of the Nix language: the lack of convenience for managing remote sources.


```nix
{ pkgs, ... }:
let
  disko = pkgs.fetchFromGitHub {
    owner = "nix-community";
    repo = "disko";
    rev = "master";
    hash = "sha256-bTMGbnfzOOxdGhMg3Y+JpGkEle8U8CExgRl+Lep9ANU=";
  };
in
{
  imports = [
    "${disko}/module.nix"
  ]

  # ...
}
```

An additional downside of this approach is that the remote source cannot be overridden at the call site.

The [URL-like remote source syntax](https://nix.dev/manual/nix/2.19/command-ref/new-cli/nix3-flake#url-like-syntax) and [`nix flake update`](https://nix.dev/manual/nix/2.19/command-ref/new-cli/nix3-flake-update) were supposed to address that, but just as with [`niv`](https://github.com/nmattia/niv/) and [`npins`](https://github.com/andir/npins), remote sources can only be managed at the top-level of a given Nix project.
This means, none of the existing implementations allows for source declarations that are fully local to a module.
The best we can currently do is pinning those remote sources with a pattern that hard-codes project-specific file system locations.

For example, suppose the module is in a subdirectory of the repository declaring a NixOS configuration:


```nix
# npins
{ ... }:
let
  sources = import ../npins;
in
{
  imports = [ "${sources.disko}/module.nix" ];

  # ...
}
```

```nix
# niv
{ ... }:
let
  sources = import ../nix/sources.nix;
in
{
  imports = [ "${sources.disko}/module.nix" ];

  # ...
}
```

```nix
# flakes
{ ... }:
let
  sources = builtins.mapAttrs
    (_: value: builtins.fetchTree value.locked)
    (builtins.fromJSON (builtins.readFile ../flake.lock)).nodes;
in
{
  imports = [ "${sources.disko}/module.nix" ];

  # ...
}
```

Apart from being error-prone and cumbersome to refactor, this setup does not allow re-using the module as it is.
It also degrades the convenience of flakes to the level of `niv` and `npins`, since the remote reference is now hidden away in the lockfile rather than being explicit and editable right there in the source.

## Requirements

1. It should be possible to declare a remote source in the module that uses it, such that the module can be re-used anywhere without modification.
2. Remote sources should be pinned persistently without manually specifying exact revisions.
3. It should be trivial to override the source declaration at the call site, while the original value should be used transparently.

## Alternatives considered

There are multiple approaches to solve this, but only the dedicated module seems viable.

### Additional module argument

An obvious and ostensibly easy to implement idea is adding source references via `_module.args`:

```nix
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {};
in
pkgs.lib.evalModules {
  modules = [
    { _module.args = { inherit sources; }; }
    ./module.nix
  ];
}
```

```nix
# module.nix
{ sources, ... }:
{
  imports = [ "${sources.disko}/module.nix" ];

  # ...
};
```

The problem is that this doesn't actually work since `imports` has to be resolved *before* the module arguments, and one therefore has to use [`specialArgs`](https://github.com/NixOS/nixpkgs/blob/7e15118af2bc1e3afae966c0e5ab996ecbd2bfda/lib/modules.nix#L76-L80).
Unfortunately, in the NixOS case [`pkgs.nixos` wraps the call to `evalModules`](https://github.com/NixOS/nixpkgs/blob/7e15118af2bc1e3afae966c0e5ab996ecbd2bfda/pkgs/top-level/all-packages.nix#L40653-L40674) in a way that does not allow setting anything but modules.
While [`nixpkgs.lib.nixosSystem` exposed in `flake.nix` does allow it](https://github.com/NixOS/nixpkgs/blob/master/flake.nix#L22-L30), there are enough issues with flakes, and Nixpkgs, and NixOS architecture to be careful with adopting those interfaces.

The alternative would be calling into [`nixos/eval-config.nix`](https://github.com/NixOS/nixpkgs/blob/7e15118af2bc1e3afae966c0e5ab996ecbd2bfda/nixos/lib/eval-config.nix) manually, but that quite involved, and [`nixos/eval-config-minimal.nix`](https://github.com/NixOS/nixpkgs/blob/7e15118af2bc1e3afae966c0e5ab996ecbd2bfda/nixos/lib/eval-config-minimal.nix) is not yet the default way to evaluate a NixOS configuration.
In any case this would defy the goal of being convenient to use, as one would require a bespoke incantation that may require substantially reworking existing setups.

But even if all that could eventually be addressed by improving Nixpkgs and NixOS facilities, the other objectives are not fulfilled with this approach, either:
- Sources references are not declared in the module explicitly, therefore the module can't be used standalone.
- There is no way of overriding the source reference at the call site of the module, only globally for a given project.

### Function wrapper

Another idea is to wrap module declarations in a function that supplies source references:

```nix
# module.nix
{ sources }:
{ ... }:
{
  imports = [ "${sources.disko}/module.nix" ];

  # ...
}
```

This offers an obvious mechanism for source overrides:

```nix
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {};
in
pkgs.lib.evalModules {
  modules = [
    (import ./module.nix { inherit sources; })
  ];
}
```

But that is about the only advantage.
The major disadvantage is that this requires explicitly importing and calling modules.
Since existing setups should definitely be preserved as they are, this would imply adding even more logic to the module system, or establishing yet another convention that requries manual intervention that is likely to be prone to errors.
In particular, without additional machinery there is no transparent use of the orginal values, and overriding is not very convenient as the `import`/`inherit` pattern does not explain on its own what it's really about.

### Source module

Finally, an approach that is native to the module system would be adding a module that allows specifying sources as option values:

```nix
{ config, lib, ... }:
{
  imports = [ "${config.sources.disko}/module.nix" ];

  sources.disko = with lib.modules.sources; {
    type = github;
    owner = "nix-community";
    repo = "disko";
  };

  # ...
}
```

The `sources` module would be an `attrsOf submodule` encoding the built-in or Nixpkgs-specific fetcher types.
It could use `builtins.unsafeGetAttrPos` to determine the call site and thus know where to look for the lockfile by default.

This would definitely need a dedicated command to update the lock file.
The command would inspect all of `config.sources` in a separate evaluation step.
Ideally it would support multiple lock file formats or allow for pluggable backends.

The fundamental problem with this is that due to the current architecture of the module system, it cannot be implemented for the same reasons as the [additional module argument](#additional-module-argument):
`imports` are evaluated eagerly, that is, before any `config` values.

## Conclusion

The result of this exploration is a need for further research into a lazy `imports` system that would allow for the following construction:

```nix
{ config, lib, nixos, ... }:
{
  modules = {
    disko = "${config.sources.disko}/module.nix";
    # the `sources` module could also be implicitly built-in for convenience
    sources = lib.modules.sources.module;
    # modules shipped with NixOS can be a supplied via `specialArgs` in the NixOS-specific `evalModules` wrapper
    nginx = nixos.services.nginx;
  };

  sources.disko = with lib.modules.sources; github {
    owner = "nix-community";
    repo = "disko";
  };

  disko = {
   # ...
  };

  nginx = {
    # ...
  };
}
```

This namespacing could potentially enable getting rid of both the `enable` pattern *and* "ambient authority" (the module system's violation of the principle of least authority where any module can override settings of any other).
But there is also a risk that this might not work at all.

For instance, it would then be possible to write:

```nix
{ nixos, ... }:
{
  modules = {
    nginx = nixos.services.nginx;
    nginx2 = nixos.services.nginx;
  };

  nginx = {
    virtualHosts.foo = {
      # ...
    };
  };

  nginx2 = {
    virtualHosts.bar = {
      # ...
    };
  };
}
```

But what would that even mean?

## Further reading

- [RFC 22: Minimal module list](https://github.com/nixos/rfcs/pull/22)
- [The Nix Hour #19: module system recursion, config vs config, common infinite recursion causes](https://www.youtube.com/watch?v=cZjOzOHb2ow)
