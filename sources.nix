{ config, lib, ... }:

let
  source = with lib; mkOptionType {
    name = "source";
    check = types.path.check;
    merge = loc: defs:
      if (length defs > 1) then
        throw ''
          The option ${showOption loc} is defined in multiple locations:

          ${concatStringsSep "\n" (map (s: "       ${s.file}") defs)}
        ''
      # TODO: process source references here
      # the resulting value should string-coerce to a store path.
      # in the simplest case this would be just a call to a Nixpkgs fetcher.
      # TODO: the module could be configured to allow IFD
      else (head defs).value;
  };
in
{
  options = with lib; rec {
    sources = mkOption {
      description = "Named source references";
      # just allow local paths as source references for now
      type = with types; attrsOf source;
      # TODO: implement proper source types, with appropriate merging
      # the top-level type should accept any of the source types that map to a Nixpkgs fetcher.
      # it could also take a list of them for redundancy.
      # something like:
      #
      #     type = let
      #       source = oneOf [ path url tarball git github ];
      #     in
      #     either source (listOf source)
      #
      # source references also should support overrides.
      # we have to assume that remote sources are immutable,
      # and if they are modules, their own dependency declarations may be broken or have diamond shapes.
      # therefore there needs to be a way to override them in place:
      #
      #     git {
      #         owner = "NixOS";
      #         repo = "nix";
      #         override.nixpkgs.git = {
      #             # ...
      #           };
      #         };
      #     }
      #
      # it should be possible to declare overrides for any depth.
      # list items could be addressed by digit strings:
      #
      #     git.override.nixpkgs."1".tarball
      #
      # TODO: source names must be globally unique.
      # remote sources could easily provoke collisions.
      # those can be worked around with overrides and patches.
      # but we still can allow some redundancy to allow keeping independent modules self-contained.
      # for example, pick the most precise reference and only error on conflicts.
      # ideally leverage domain-specific knowledge from the fetcher type transparently.
      default = { };
    };
    locked-sources = mkOption {
      description = "Lock file for source references";
      type = with types; attrsOf path;
      # TODO: specify the lock file format, needs source types
      #
      #     type =
      #       with lib; with types;
      #       let
      #         lockfileReferences =
      #           let
      #             # names are source names of nested dependencies
      #             sourceNames = attrsOf (either sourceNames lockReference);
      #             lockReference = either sourceType (nonEmptylistOf sourceType);
      #             sourceType = oneOf (map typeReference (attrNames lockfile));
      #             # map from source type to hash of the source reference
      #             typeReference = type: { ${type} = mkOption { type = string; }; };
      #           in
      #           sourceNames;
      #         lockfileEntry = type: mkOption {
      #           default = null;
      #           type = nullOr (attrsOf # hash of the source reference
      #             (submodule {
      #               original = mkOption { inherit type; };
      #               locked = mkOption { inherit type; };
      #               override = mkOption { type = lockfileReferences; };
      #               # XXX: in contrast to `flake.lock` this cannot be a NAR hash.
      #               # currently it's not possible to compute a store path from a NAR hash in the Nix language.
      #               storePath = mkOption { type = path; };
      #             }));
      #         };
      #       in
      #       submodule {
      #         path = lockFileEntry path;
      #         url = lockFileEntry url;
      #         tarball = lockFileEntry tarball;
      #         git = lockFileEntry git;
      #         github = lockFileEntry github;
      #       };
      #
      # TODO: check that all source types for a declaration produce the same store path.
      # TODO: figure out what to do about the recursive case where fetched sources have dependencies themselves.
      # probably use their lockfile if it exists.
      # otherwise create one and put it into a wrapper store object around the immutable fetch result.
      # the wrapper would also refer to store objects of recursive dependencies.
      # this would naturally represent the dependency closure.
      # this wrapper is specific to the caller's closure.
      # hence overrides declared by the caller can directly replace the dependency's source references in the wrapper lock file,
      # TODO: transform `config.sources` to the lock file format
      default = config.sources;
    };
    modules = mkOption {
      description = "Module references for phased import";
      # TODO: a module declaration could also be an attribute set.
      # then it would be possible to declare a field like
      #
      #     override.type = attrsOf (nullOr (either path deferredModule))
      #
      # this would allow replacing or disabling upstream modules by attribute name.
      type = with types; attrsOf (either path deferredModule);
      default = { };
    };
    imports = mkOption {
      type = with types; listOf (either path deferredModule);
      # TODO: this doesn't make module imports lazy and introduces substantial overhead.
      # but it allows for some serious caching!
      # for example, instead of returning complete modules, they can be pre-processed.
      # one possibility is to evaluate them at collection time and create a light-weight replacement.
      # it could shift rare but expensive computation into separate files.
      # or re-write the expression to a single file.
      # this way we could save some time in the final evaluation phase.
      default = (attrsets.mapAttrsToList (_: x: x) config.modules) ++ [{
        # prevent type errors
        options = { inherit sources modules; };
      }];
    };
  };
}
