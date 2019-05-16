{ pkgs ? import <nixpkgs> {},
  target-os ? "android" }:
with pkgs;

let
  projectDeps = import ./default.nix { inherit target-os; };
  platform = callPackage ./nix/platform.nix { inherit target-os; };
  useFastlanePkg = (platform.targetAndroid && !stdenv'.isDarwin);
  # TODO: Try to use stdenv for iOS. The problem is with building iOS as the build is trying to pass parameters to Apple's ld that are meant for GNU's ld (e.g. -dynamiclib)
  stdenv' = stdenvNoCC;
  mkShell' = mkShell.override { stdenv = stdenv'; };

in mkShell' {
  buildInputs = [
    # utilities
    bash
    curl
    file
    git
    gnumake
    jq
    ncurses
    lsof # used in scripts/start-react-native.sh
    ps # used in scripts/start-react-native.sh
    unzip
    wget
  ];
  inputsFrom = [ projectDeps ];
  TARGET_OS = target-os;
  shellHook = projectDeps.shellHook;
}
