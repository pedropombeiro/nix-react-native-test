{ system ? builtins.currentSystem
, config ? { android_sdk.accept_license = true; }, overlays ? []
, pkgs ? (import <nixpkgs> { inherit system config overlays; })
, target-os }:

let
  platform = pkgs.callPackage ./nix/platform.nix { inherit target-os; };
  # TODO: Try to use stdenv for iOS. The problem is with building iOS as the build is trying to pass parameters to Apple's ld that are meant for GNU's ld (e.g. -dynamiclib)
  _stdenv = pkgs.stdenvNoCC;
  gradle = pkgs.gradle_4_10;
  statusMobile = pkgs.callPackage ./nix/mobile { inherit target-os config pkgs gradle; stdenv = _stdenv; nodejs = nodejs'; yarn = yarn'; };
  nodejs' = pkgs.nodejs-10_x;
  yarn' = pkgs.yarn.override { nodejs = nodejs'; };
  nodePkgBuildInputs = with pkgs; [
    nodejs'
    python27 # for e.g. gyp
    yarn'
  ];
  selectedSources =
    _stdenv.lib.optional platform.targetMobile statusMobile;

in with _stdenv; mkDerivation rec {
  name = "nix-react-native-test-build-env";

  buildInputs = with _stdenv; with pkgs; [
    clojure
    leiningen
    maven
    watchman
    gradle openjdk
  ] ++ nodePkgBuildInputs
    ++ lib.optional isDarwin cocoapods
    ++ lib.optional (isDarwin && !platform.targetIOS) clang
    ++ lib.optional (!isDarwin) gcc7
    ++ lib.catAttrs "buildInputs" selectedSources;
  shellHook = lib.concatStrings (lib.catAttrs "shellHook" selectedSources);
}
