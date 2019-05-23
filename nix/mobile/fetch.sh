#!/bin/bash

_tmp=$(mktemp)
sort $1 | uniq > $_tmp
echo "{}:

{"
while read depurl
do
    if [ -n "$depurl" ]; then
        host="https://jcenter.bintray.com"
        if [[ $depurl = 'https://dl.google.com/dl/android/maven2'* ]]; then
            host="https://dl.google.com/dl/android/maven2"
        fi
        deppath="${depurl/$host\//}"
        pom_sha256=$(nix-prefetch-url "$depurl.pom" 2> /dev/null)
        jar_sha256=$(nix-prefetch-url "$depurl.jar" 2> /dev/null)
        type='jar'
        if [ -z "$jar_sha256" ]; then
            jar_sha256=$(nix-prefetch-url "$depurl.aar" 2> /dev/null)
            [ -n "$jar_sha256" ] && type='aar'
        fi

        if [ -z "$pom_sha256" ] && [ -z "$jar_sha256" ] && [ -z "$aar_sha256" ]; then
            echo "Warning: failed to download $depurl" > /dev/stderr
            echo "Exiting." > /dev/stderr
        fi

        echo "  \"$depurl\" = {
    host = \"$host\";
    path = \"$deppath\";
    pom-sha256 = \"$pom_sha256\";
    type = \"$type\";
    jar-sha256 = \"$jar_sha256\";
  };"
    fi
done < $_tmp

rm $_tmp

echo "}"
