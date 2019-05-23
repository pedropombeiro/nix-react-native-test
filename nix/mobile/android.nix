{ config, stdenv, lib, pkgs, androidenv, callPackage, fetchurl, gradle, perl, openjdk, nodejs, yarn, zlib }:

with stdenv;

let
  androidComposition = androidenv.composeAndroidPackages {
    toolsVersion = "26.1.1";
    platformToolsVersion = "28.0.2";
    buildToolsVersions = [ "28.0.3" ];
    includeEmulator = false;
    platformVersions = [ "28" ];
    includeSources = false;
    includeDocs = false;
    includeSystemImages = false;
    systemImageTypes = [ "default" ];
    abiVersions = [ "armeabi-v7a" ];
    lldbVersions = [ "2.0.2558144" ];
    cmakeVersions = [ "3.6.4111459" ];
    includeNDK = true;
    ndkVersion = "19.2.5345600";
    useGoogleAPIs = false;
    useGoogleTVAddOns = false;
    includeExtras = [ "extras;android;m2repository" "extras;google;m2repository" ];
  };
  src =
    let
      src = ./../..; # Import the root /android folder clean of any build artifacts

      mkFilter = { dirsToInclude, dirsToExclude, root }: path: type:
        let
          inherit (lib) elem elemAt splitString;
          baseName = baseNameOf (toString path);
          subpath = elemAt (splitString "${toString root}/" path) 1;
          spdir = elemAt (splitString "/" subpath) 0;

        in lib.cleanSourceFilter path type && ((elem spdir dirsToInclude) && ! (
          # Filter out version control software files/directories
          (type == "directory" && (elem baseName dirsToExclude)) ||
          # Filter out editor backup / swap files.
          lib.hasSuffix "~" baseName ||
          builtins.match "^\\.sw[a-z]$" baseName != null ||
          builtins.match "^\\..*\\.sw[a-z]$" baseName != null ||

          # Filter out generated files.
          lib.hasSuffix ".o" baseName ||
          lib.hasSuffix ".so" baseName ||
          # Filter out nix-build result symlinks
          (type == "symlink" && lib.hasPrefix "result" baseName)
        ));
      in builtins.filterSource
          (mkFilter {
            dirsToInclude = [ "android" ];
            dirsToExclude = [ ".git" ".svn" "CVS" ".hg" ".gradle" "build" "intermediates" ];
            root = src;
          })
      src;
  licensedAndroidEnv = callPackage ./licensed-android-sdk.nix { inherit androidComposition; };
  nodePackages = import ./node2nix { inherit pkgs nodejs lib; };
  nodeDeps = nodePackages.package;

  mavenLocal = import ./gradle-deps.nix { };
  rnMavenLocal = import ./reactnative-gradle-deps.nix { };
  fakeMavenRepoBuilder = callPackage ./maven-repo-builder.nix { inherit stdenv; };
  fakeMavenRepo = fakeMavenRepoBuilder mavenLocal "gradle-deps";
  fakeRNMavenRepo = fakeMavenRepoBuilder rnMavenLocal "reactnative-gradle-deps";

  jsc-filename = "jsc-android-236355.1.1";
  react-native-deps = callPackage ./reactnative-android-native-deps.nix { inherit jsc-filename; };

  # fake build to pre-download deps into fixed-output derivation
  deps = stdenv.mkDerivation {
    name = "gradle-install-android-archives";
    inherit src;
    buildInputs = [ gradle perl zlib ];
    unpackPhase = ''
      cp -R $src/* .
      chmod -R u+w android

      # Copy fresh RN maven dependencies and make them writable, otherwise Gradle copy fails
      cp -R ${react-native-deps}/deps ./deps
      chmod -R u+w ./deps

      # Copy fresh node_modules and adjust permissions
      rm -rf ./node_modules
      mkdir -p ./node_modules
      cp -R ${nodeDeps}/lib/node_modules/nix_react_native_test/node_modules .
      chmod u+w -R ./node_modules/react-native
    '';
    patchPhase = ''
      # Patch maven central repository with our own local directory. This prevents the builder from downloading Maven artifacts
      substituteInPlace android/build.gradle \
        --replace "google()" "maven { url \"${fakeMavenRepo}\" }" \
        --replace "\$rootDir/../node_modules/react-native/android" "${fakeRNMavenRepo}"

      # Patch prepareJSC so that it doesn't try to download from registry
      substituteInPlace node_modules/react-native/ReactAndroid/build.gradle \
        --replace "prepareJSC(dependsOn: downloadJSC)" "prepareJSC(dependsOn: createNativeDepsDirectories)" \
        --replace "def jscTar = tarTree(downloadJSC.dest)" "def jscTar = tarTree(new File(\"$(pwd)/deps/${jsc-filename}.tar.gz\"))"
    '';
    buildPhase = ''
      export JAVA_HOME="${openjdk}"
      export ANDROID_HOME="${licensedAndroidEnv}"
      export ANDROID_SDK_ROOT="$ANDROID_HOME"
      export ANDROID_NDK_ROOT="${androidComposition.androidsdk}/libexec/android-sdk/ndk-bundle"
      export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
      export ANDROID_NDK="$ANDROID_NDK_ROOT"
      export PATH="$ANDROID_HOME/bin:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools:$PATH"

      export REACT_NATIVE_DEPENDENCIES="$(pwd)/deps"

      export GRADLE_USER_HOME=$(mktemp -d)
      ( cd android
        LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${stdenv.lib.makeLibraryPath [ zlib ]} gradle --no-daemon react-native-android:installArchives
      )
    '';
    installPhase = ''
      rm -rf $out
      mkdir -p $out
      cp -R node_modules/ $out

      # Patch prepareJSC so that it doesn't subsequently try to build NDK libs
      substituteInPlace $out/node_modules/react-native/ReactAndroid/build.gradle \
        --replace "packageReactNdkLibs(dependsOn: buildReactNdkLib, " "packageReactNdkLibs(" \
        --replace "./deps/${jsc-filename}.tar.gz" "${react-native-deps}/deps/${jsc-filename}.tar.gz" 

      # Generate Maven directory structure in node_modules/react-native/android from existing cache
      # perl code mavenizes pathes (com.squareup.okio/okio/1.13.0/a9283170b7305c8d92d25aff02a6ab7e45d06cbe/okio-1.13.0.jar -> com/squareup/okio/okio/1.13.0/okio-1.13.0.jar)
      find $GRADLE_USER_HOME/caches/modules* -type f -regex '.*\.\(jar\|pom\)' \
        | perl -pe 's#(.*/([^/]+)/([^/]+)/([^/]+)/[0-9a-f]{30,40}/([^/\s]+))$# ($x = $2) =~ tr|\.|/|; "install -Dm444 $1 \$out/node_modules/react-native/android/$x/$3/$4/$5" #e' \
        | sh
    '';
    dontPatchELF = true; # The ELF types are incompatible with the host platform, so let's not even try
    noAuditTmpdir = true;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

in
  {
    inherit androidComposition;

    buildInputs = [ deps openjdk gradle ];
    shellHook = ''
      export JAVA_HOME="${openjdk}"
      export ANDROID_HOME=${licensedAndroidEnv}
      export ANDROID_SDK_ROOT="$ANDROID_HOME"
      export ANDROID_NDK_ROOT="${androidComposition.androidsdk}/libexec/android-sdk/ndk-bundle"
      export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
      export ANDROID_NDK="$ANDROID_NDK_ROOT"
      export PATH="$ANDROID_HOME/bin:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools:$PATH"
    '' +
    ''
      if [ -d ./node_modules ]; then
        chmod u+w -R ./node_modules
        rm -rf ./node_modules || exit
      fi
      echo "Copying node_modules from Nix store (${deps}/node_modules)..."
      # mkdir -p node_modules # node_modules/react-native/ReactAndroid
      time cp -HR --preserve=all ${deps}/node_modules .
      echo "Done"

      # This avoids RN trying to download dependencies. Maybe we need to wrap this in a special RN environment derivation
      export REACT_NATIVE_DEPENDENCIES="${react-native-deps}/deps"

      rndir='node_modules/react-native'
      rnabuild="$rndir/ReactAndroid/build"
      chmod 744 $rndir/scripts/.packager.env \
                $rndir/ReactAndroid/build.gradle \
                $rnabuild/outputs/logs/manifest-merger-release-report.txt \
                $rnabuild/intermediates/library_manifest/release/AndroidManifest.xml \
                $rnabuild/intermediates/aapt_friendly_merged_manifests/release/processReleaseManifest/aapt/AndroidManifest.xml \
                $rnabuild/intermediates/aapt_friendly_merged_manifests/release/processReleaseManifest/aapt/output.json \
                $rnabuild/intermediates/incremental/packageReleaseResources/compile-file-map.properties \
                $rnabuild/intermediates/incremental/packageReleaseResources/merger.xml \
                $rnabuild/intermediates/merged_manifests/release/output.json \
                $rnabuild/intermediates/symbols/release/R.txt \
                $rnabuild/intermediates/res/symbol-table-with-package/release/package-aware-r.txt
      chmod u+w -R $rnabuild

      export PATH="$PATH:${deps}/node_modules/.bin"
    '';
  }
