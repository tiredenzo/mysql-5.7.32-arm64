#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p inputs
# Recover the public build inputs omitted from Git and verify before use.
check() {
  python3 - "$1" "$2" <<'PY'
import hashlib, pathlib, sys
p = pathlib.Path(sys.argv[1])
sys.exit(0 if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest() == sys.argv[2] else 1)
PY
}
fetch() {
  local name=$1 digest=$2 method=$3 location=$4
  check "inputs/$name" "$digest" && return 0
  local temporary
  temporary=$(mktemp "inputs/.download.XXXXXX")
  if [ "$method" = curl ]; then
    curl --fail --location --retry 2 "$location" -o "$temporary"
  elif [ "$method" = api ]; then
    gh api "$location" > "$temporary"
  elif [ "$method" = patch ]; then
    gh api -H 'Accept: application/vnd.github.patch' "$location" > "$temporary"
  else
    gh release download "$location" --repo "$method" --pattern "$name" --output "$temporary" --clobber
  fi
  check "$temporary" "$digest" || { rm -f "$temporary"; echo "Checksum mismatch: $name" >&2; exit 1; }
  mv "$temporary" "inputs/$name"
}
oracle=https://repo.mysql.com/apt/debian/pool/mysql-5.7/m/mysql-community
fetch mysql-community_5.7.32.orig.tar.gz 1f4b59b43f82de4ccf4ba9cfce087318a192012a752aee8f66ca16f73bb082c9 curl "$oracle/mysql-community_5.7.32.orig.tar.gz"
fetch mysql-community_5.7.32-1debian10.debian.tar.xz 472c5935af78f7a93e3476f085cf1f890078f81308bf0410c5b61013f2d68f6f curl "$oracle/mysql-community_5.7.32-1debian10.debian.tar.xz"
fetch boost_1_59_0.tar.bz2 727a932322d94287b62abb1bd2d41723eec4356a7728909e38adb65ca25241ca curl https://archives.boost.io/release/1.59.0/source/boost_1_59_0.tar.bz2
# GitHub operations deliberately use gh. Log in if it reports missing/invalid auth:
# gh auth login -h github.com
fetch openssl-1.1.1g.tar.gz ddb04774f1e32f0c49751e21b67216ac87852ceb056b75209af2443400636d46 openssl/openssl OpenSSL_1_1_1g
fetch openssl-aarch64-static-pic.d741debb.patch c6babf75ab3899db410749bc530f392c8da24b1e6099170b540ca7e5993225f0 patch repos/openssl/openssl/commits/d741debb320bf54e8575d35603a44d4eb40fa1f9
fetch googletest-ec44c6c.tar.gz 19476bd60bd9732f52c1ea56fd0e712d06c817cf16deaf003ee7fcca4960fd7d api repos/google/googletest/tarball/ec44c6c1675c25b9827aacd08c02433cccde7780
fetch gosu-arm64 ff6f0b36315d2013d4fcc442cded0e0403d6bb29abc4cd6f94f2bde90bf97a38 tianon/gosu 1.12
echo 'All inputs match their pinned SHA256 hashes.'
