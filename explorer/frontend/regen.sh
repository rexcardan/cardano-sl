#! /usr/bin/env nix-shell
#! nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs-channels/archive/nixos-unstable.tar.gz -i bash -p nodePackages.bower2nix nodePackages.node2nix

bower2nix bower.json bower-generated.nix

node2nix -6 -c composition.nix -d

sed -i \
    -e 's/sources."uglify-js-3.*"/sources."uglify-js-2.8.29"/g' \
    node-packages.nix


# Manual steps:
# - Add src function argument to node-packages.nix and composition.nix
# - change src attribute of nodePackages.package to not be ./.
# - Check that uglify-js version 3 is not used anywhere.
