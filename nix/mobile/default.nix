{ config, stdenv, target-os, callPackage, pkgs, nodejs, yarn, gradle }:

with stdenv;

let
  platform = callPackage ../platform.nix { inherit target-os; };
  xcodewrapperArgs = {
    version = "10.1";
  };
  xcodeWrapper = xcodeenv.composeXcodeWrapper xcodewrapperArgs;
  androidPlatform = callPackage ./android.nix { inherit config pkgs gradle nodejs; };
  selectedSources =
    lib.optional platform.targetAndroid androidPlatform;

in
  {
    inherit (androidPlatform) androidComposition;
    inherit xcodewrapperArgs;

    buildInputs =
      lib.catAttrs "buildInputs" selectedSources ++
      lib.optional (platform.targetIOS && isDarwin) xcodeWrapper;
    shellHook = lib.concatStrings (lib.catAttrs "shellHook" selectedSources);
  }
