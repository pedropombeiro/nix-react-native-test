{ system ? builtins.currentSystem
, config ? { android_sdk.accept_license = true; }, overlays ? []
, pkgs ? (import <nixpkgs> { inherit system config overlays; })
, target-os }:

with pkgs;
  let
    platform = callPackage ./nix/platform.nix { inherit target-os; };
    # TODO: Try to use stdenv for iOS. The problem is with building iOS as the build is trying to pass parameters to Apple's ld that are meant for GNU's ld (e.g. -dynamiclib)
    _stdenv = stdenvNoCC;
    statusMobile = callPackage ./nix/mobile { inherit target-os config; stdenv = _stdenv; };
    nodejs' = nodejs-10_x;
    yarn' = yarn.override { nodejs = nodejs'; };
    nodeInputs = import ./nix/global-node-packages/output {
      # The remaining dependencies come from Nixpkgs
      inherit pkgs;
      nodejs = nodejs';
    };
    yarn2nix = import ( fetchFromGitHub { 
      owner = "moretea";
      repo = "yarn2nix";
      rev = "3cc020e384ce2a439813adb7a0cc772a034d90bb";
      sha256 = "0h2kzdfiw43rbiiffpqq9lkhvdv8mgzz2w29pzrxgv8d39x67vr9";
      name = "yarn2nix-source";
    } ) { nodejs = nodejs'; yarn = yarn'; };
    rnPackage = yarn2nix.mkYarnPackage {
      name = "react-native-packages";
      src = ./.;
      packageJson = ./package.json;
      yarnLock = ./yarn.lock;
      # NOTE: this is optional and generated dynamically if omitted
      yarnNix = ./yarn.nix;
    };    
    nodePkgBuildInputs = [
      nodejs'
      python27 # for e.g. gyp
      yarn'
      rnPackage
    ] ++ (builtins.attrValues nodeInputs);
    selectedSources =
      lib.optional platform.targetMobile statusMobile;

  in _stdenv.mkDerivation rec {
    name = "nix-react-native-test-build-env";

    buildInputs = with _stdenv; [
      clojure
      leiningen
      maven
      watchman
    ] ++ nodePkgBuildInputs
      ++ lib.optional isDarwin cocoapods
      ++ lib.optional (isDarwin && !platform.targetIOS) clang
      ++ lib.optional (!isDarwin) gcc7
      ++ lib.catAttrs "buildInputs" selectedSources;
    shellHook = lib.concatStrings (lib.catAttrs "shellHook" selectedSources);
  }
