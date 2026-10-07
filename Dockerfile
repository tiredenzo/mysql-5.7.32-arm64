# All executable stages use the pinned native ARM64 Debian 10.7 base.
FROM debian@sha256:01b65c2928fed9427e59a679e287a75d98551ea2061cf03c61be0c7e1fc40fef AS runtime-base
RUN test "$(dpkg --print-architecture)" = arm64 \
    && groupadd -r mysql && useradd -r -g mysql mysql \
    && printf '%s\n' \
      'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20210111T000000Z buster main' \
      'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/20210111T000000Z buster/updates main' \
      > /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      gnupg dirmngr pwgen openssl perl xz-utils psmisc \
      libaio1 libnuma1 libatomic1 libncurses6 libtinfo6 libmecab2 \
      libldap-2.4-2 libsasl2-2 zlib1g \
    && rm -rf /var/lib/apt/lists/*

FROM runtime-base AS build-dependencies
ARG BUILD_JOBS=6
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake bison libaio-dev libncurses5-dev libnuma-dev \
      libmecab-dev libldap2-dev libsasl2-dev zlib1g-dev python3 \
      file binutils pkg-config patch \
    && rm -rf /var/lib/apt/lists/*
COPY inputs/*.tar.* inputs/*.patch inputs/SHA256SUMS /inputs/
RUN cd /inputs && sha256sum -c SHA256SUMS \
    && mkdir -p /src/mysql /deps /build /packages \
    && tar -xzf mysql-community_5.7.32.orig.tar.gz -C /src/mysql --strip-components=1 \
    && tar -xJf mysql-community_5.7.32-1debian10.debian.tar.xz -C /src/mysql \
    && tar -xjf boost_1_59_0.tar.bz2 -C /deps \
    && mkdir /deps/googletest-release-1.8.0 \
    && tar -xzf googletest-ec44c6c.tar.gz -C /deps/googletest-release-1.8.0 --strip-components=1 \
    && tar -xzf openssl-1.1.1g.tar.gz -C /src
RUN cd /src/openssl-1.1.1g \
    && patch --fuzz=0 -p1 < /inputs/openssl-aarch64-static-pic.d741debb.patch \
    && ./Configure linux-aarch64 no-shared --prefix=/deps/openssl -fPIC \
    && make -j"$BUILD_JOBS" && make install_sw
# Verify the demonstrated ARM64 static-archive/shared-plugin failure before
# compiling MySQL. The official patch changes internal ASM symbol visibility.
RUN gcc -shared -Wl,--whole-archive /deps/openssl/lib/libcrypto.a \
      -Wl,--no-whole-archive -ldl -pthread -o /tmp/openssl-static-link-probe.so \
    && rm /tmp/openssl-static-link-probe.so

FROM build-dependencies AS builder
ARG BUILD_JOBS=6
COPY build/compile.sh /build/compile.sh
RUN --mount=type=cache,id=oracle-mysql5732-arm64,target=/build/mysql,sharing=locked \
    bash /build/compile.sh
COPY build/package.sh /build/package.sh
RUN bash /build/package.sh

FROM runtime-base AS final
ENV GOSU_VERSION=1.12 MYSQL_MAJOR=5.7 MYSQL_VERSION=5.7.32-1debian10+arm64.1
COPY inputs/gosu-arm64 /usr/local/bin/gosu
RUN echo 'ff6f0b36315d2013d4fcc442cded0e0403d6bb29abc4cd6f94f2bde90bf97a38  /usr/local/bin/gosu' | sha256sum -c - \
    && chmod +x /usr/local/bin/gosu && gosu nobody true
COPY --from=builder /packages/ /tmp/mysql-packages/
RUN dpkg --unpack /tmp/mysql-packages/*.deb
COPY reference/etc-mysql/ /etc/mysql/
# Keep the pinned official configuration when dpkg encounters changed conffiles.
RUN dpkg --force-confold --configure -a && rm -rf /tmp/mysql-packages
COPY reference/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN echo 'd17f477f0476783cb6014dd0d0fee23d8817df1e9a5e7168861940a6ca36339f  /usr/local/bin/docker-entrypoint.sh' | sha256sum -c - \
    && chmod +x /usr/local/bin/docker-entrypoint.sh \
    && ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh \
    && mkdir -p /docker-entrypoint-initdb.d /var/lib/mysql /var/lib/mysql-files /var/run/mysqld \
    && chown -R mysql:mysql /var/lib/mysql /var/lib/mysql-files /var/run/mysqld \
    && chmod 1777 /var/run/mysqld /var/lib/mysql \
    && chmod 770 /var/lib/mysql-files
COPY --from=builder /build/provenance/ /usr/share/mysql/arm64-build/
LABEL org.opencontainers.image.title="Oracle MySQL 5.7.32 native ARM64" \
      org.opencontainers.image.version="5.7.32" \
      local.mysql.reference="mysql@sha256:e08834258fcc0efd01df358222333919df53d4a0d9b2a54da05b204b822e3b7b"
VOLUME /var/lib/mysql
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 3306 33060
CMD ["mysqld"]
