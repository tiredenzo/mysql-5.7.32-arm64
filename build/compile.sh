#!/bin/bash
set -euo pipefail
test "$(uname -m)" = aarch64
mkdir -p /build/mysql /build/provenance
cd /build/mysql
cmake /src/mysql \
  -DWITH_BOOST=/deps/boost_1_59_0 -DWITH_GMOCK=/deps -DDOWNLOAD_ROOT=/deps \
  -DBUILD_CONFIG=mysql_release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DINSTALL_DOCDIR=share/mysql/docs \
  -DINSTALL_DOCREADMEDIR=share/mysql \
  -DINSTALL_INCLUDEDIR=include/mysql \
  -DINSTALL_INFODIR=share/mysql/docs \
  -DINSTALL_LIBDIR=lib/aarch64-linux-gnu \
  -DINSTALL_MANDIR=share/man \
  -DINSTALL_MYSQLSHAREDIR=share/mysql \
  -DINSTALL_MYSQLTESTDIR=lib/mysql-test \
  -DINSTALL_PLUGINDIR=lib/mysql/plugin \
  -DINSTALL_SBINDIR=sbin \
  -DINSTALL_SUPPORTFILESDIR=share/mysql \
  -DSYSCONFDIR=/etc/mysql \
  -DMYSQL_UNIX_ADDR=/var/run/mysqld/mysqld.sock \
  -DWITH_SSL=/deps/openssl \
  -DWITH_INNODB_MEMCACHED=1 -DWITH_MECAB=system -DWITH_NUMA=ON \
  '-DCOMPILATION_COMMENT=MySQL Community Server (GPL)' \
  -DINSTALL_LAYOUT=DEB -DDEB_PRODUCT=community
# Fail instead of accidentally linking the distro's OpenSSL.
grep -q 'OPENSSL_LIBRARY:FILEPATH=/deps/openssl/lib/libssl.a' CMakeCache.txt
grep -q 'CRYPTO_LIBRARY:FILEPATH=/deps/openssl/lib/libcrypto.a' CMakeCache.txt
make -j"${BUILD_JOBS:-6}"
make install DESTDIR=/install
cp CMakeCache.txt /build/provenance/
cp /inputs/SHA256SUMS /build/provenance/
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' > /build/provenance/build-packages.tsv
gcc --version > /build/provenance/compiler.txt
for executable in /install/usr/sbin/mysqld /install/usr/bin/mysql /install/usr/bin/mysqldump; do
  file "$executable"
  readelf -h "$executable" | grep 'Machine:.*AArch64'
  ! readelf -d "$executable" | grep -E 'NEEDED.*(libssl|libcrypto)'
  strings "$executable" | grep 'OpenSSL 1.1.1g'
  "$executable" --version
done > /build/provenance/binaries.txt
