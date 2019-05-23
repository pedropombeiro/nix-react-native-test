{ stdenv, lib, fetchurl }:

# Put the downloaded plugins in a fake Maven repository
source: name: stdenv.mkDerivation {
  name = "fake-maven-repo-${name}";
  buildCommand = ''
    mkdir -p $out
    cd $out
  '' +
  (lib.concatMapStrings (dep: 
    let
      url = "${dep.host}/${dep.path}";
      pom-download = if dep.pom-sha256 != "" then fetchurl { url = "${url}.pom"; sha256 = dep.pom-sha256; } else "";
      jar-download = if dep.jar-sha256 != "" then fetchurl { url = "${url}.${dep.type}"; sha256 = dep.jar-sha256; } else "";
      fileName = lib.last (lib.splitString "/" dep.path);
      directory = lib.removeSuffix fileName dep.path;
    in
      ''
        mkdir -p ${directory}
      '' +
      (lib.optionalString (pom-download != "") ''
        cp "${pom-download}" "${dep.path}.pom"
      '') +
      (lib.optionalString (jar-download != "") ''
        cp "${jar-download}" "${dep.path}.${dep.type}"
      ''))
    (lib.attrValues source));
}
