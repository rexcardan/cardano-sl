let
  localLib = import ../../lib.nix;
in
{ system ? builtins.currentSystem
, config ? {}
, gitrev ? localLib.commitIdFromGitRepo ../../.git
, pkgs ? (import (localLib.fetchNixPkgs) { inherit system config; })
, cardano-sl-explorer
}:

with pkgs.lib;

let
  cleanSourceFilter = with pkgs.stdenv;
    name: type: let baseName = baseNameOf (toString name); in ! (
      # Filter out .git repo
      (type == "directory" && baseName == ".git") ||
      # Filter out editor backup / swap files.
      lib.hasSuffix "~" baseName ||
      builtins.match "^\\.sw[a-z]$" baseName != null ||
      builtins.match "^\\..*\\.sw[a-z]$" baseName != null ||

      # Filter out locally generated/downloaded things.
      baseName == "bower_components" ||
      (type == "directory" && (baseName == "node_modules" || baseName == "dist")) ||

      # Filter out the files which I'm editing often.
      lib.hasSuffix ".nix" baseName ||
      # Filter out nix-build result symlinks
      (type == "symlink" && lib.hasPrefix "result" baseName)
    );

  src = builtins.filterSource cleanSourceFilter ./.;

  bowerComponents = pkgs.buildBowerComponents {
    name = "cardano-sl-explorer-frontend-deps";
    generated = ./bower-generated.nix;
    inherit src;
  };

  nodePackages = import ./composition.nix {
    inherit pkgs system;
    inherit src;
  };

  # p-d-l does not build with our main version of nixpkgs.
  # Needs to use something off 17.03 branch.
  oldHaskellPackages = (import (fetchTarball https://github.com/NixOS/nixpkgs/archive/cb90e6a0361554d01b7a576af6c6fae4c28d7513.tar.gz) {}).pkgs.haskell.packages.ghc802.override {
    overrides = self: super: {
      purescript-derive-lenses = oldHaskellPackages.callPackage ./purescript-derive-lenses.nix {};
    };
  };

  frontendBuildInputs = [
    oldHaskellPackages.purescript-derive-lenses
    cardano-sl-explorer
  ];

in
  nodePackages // rec {
    inherit bowerComponents;

    dist = pkgs.runCommand "cardano-sl-explorer-frontend" {} ''
      # scratch directory for uglify-js
      mkdir home  # fixme: just use HOME=$(pwd)
      export HOME=$(pwd)/home
      # export HOME=$(pwd)

      # needs a writeable version of package
      cp -R ${package}/lib/node_modules/cardano-sl-explorer .
      chmod -R u+w cardano-sl-explorer
      cd cardano-sl-explorer

      # webpack config is patched to output here
      mkdir $out

      sed -i -e "s/@GITREV@/${gitrev}/" webpack.config.babel.js

      # run the build:prod script
      export PATH=$(pwd)/node_modules/.bin:${pkgs.purescript}/bin:$PATH
      export NODE_ENV=production
      webpack --config webpack.config.babel.js
    '';

    package = nodePackages.package.override (oldAttrs: {
      dontNpmInstall = true; # handled by nix
      postInstall = ''
        rm -rf .psci_modules .pulp-cache bower_components output result

        # purescript code generation
        cardano-explorer-hs2purs --bridge-path src/Generated/
        ./scripts/generate-explorer-lenses.sh

        # frontend dependencies
        ln -s ${bowerComponents}/bower_components .

        # patch build recipe for nix
        echo "patching webpack.config.babel.js"
        sed -e "s/COMMIT_HASH.*/COMMIT_HASH': '\"@GITREV@\"',/" \
            -e "s/import GitRevisionPlugin.*//" \
            -e "s/path:.*/path: process.env.out,/" \
            -e "/new ProgressPlugin/d" \
            -i webpack.config.babel.js

        echo "patching build:prod script"
        sed -i -e "s=./node_modules/.bin/rimraf dist && mkdir dist && ==" package.json

        patchShebangs node_modules
      '';
      buildInputs = oldAttrs.buildInputs ++ frontendBuildInputs;
    });

    # nodePackages.shell.override doesn't work
    # https://github.com/svanderburg/node2nix/issues/31
    shell = pkgs.stdenv.mkDerivation {
      name = "explorer-frontend-shell";
      buildInputs = with pkgs; [ nodejs-6_x yarn pkgs.nodePackages.bower purescript ]
          ++ frontendBuildInputs;
      src = null;
    };
  }
