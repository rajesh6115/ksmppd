ARG DEBIAN_VERSION=bookworm-20250317-slim

# Debian's kannel-dev provides gw-config, gwlib headers, and libgwlib.a (1.4.5);
# the other -dev packages satisfy the libraries listed by gw-config --libs
FROM debian:${DEBIAN_VERSION} AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential cmake pkg-config kannel-dev libevent-dev libxml2-dev \
        libssl-dev libpq-dev libmariadb-dev libmariadb-dev-compat libpam0g-dev \
        libpcre3-dev libsqlite3-dev libhiredis-dev freetds-dev libnsl-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src/ksmppd
COPY . .
ARG KSMPPD_GIT_VERSION=""
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DKSMPPD_GIT_VERSION="${KSMPPD_GIT_VERSION}" \
    && cmake --build build -j"$(nproc)" \
    && cmake --install build --prefix /opt/ksmppd

# The kannel package pulls in the shared libraries gwlib was built against
FROM debian:${DEBIAN_VERSION}
RUN apt-get update \
    && apt-get install -y --no-install-recommends kannel libevent-2.1-7 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --no-create-home ksmppd
COPY --from=build /opt/ksmppd /opt/ksmppd
USER ksmppd
EXPOSE 2345 14010
ENTRYPOINT ["/opt/ksmppd/bin/ksmppd"]
CMD ["/opt/ksmppd/share/ksmppd/ksmppd.conf"]
