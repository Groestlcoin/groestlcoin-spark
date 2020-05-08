FROM node:12.16-slim as builder

ARG DEVELOPER
ARG STANDALONE=1
ENV STANDALONE=$STANDALONE

# Install build c-lightning for third-party packages (c-lightning/groestlcoind)
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates gpg dirmngr wget  \
    $([ -n "$STANDALONE" ] || echo "autoconf automake build-essential gettext libtool libgmp-dev \
                                     libsqlite3-dev python python3 python3-mako wget zlib1g-dev")

ENV LIGHTNINGD_VERSION=master

RUN [ -n "$STANDALONE" ] || ( \
    git clone https://github.com/Groestlcoin/lightning.git /opt/lightningd \
    && cd /opt/lightningd \
    && git checkout $LIGHTNINGD_VERSION \
    && DEVELOPER=$DEVELOPER ./configure \
    && make)

# Install groestlcoind
ENV GROESTLCOIN_VERSION 2.18.2
ENV GROESTLCOIN_FILENAME groestlcoin-$GROESTLCOIN_VERSION-x86_64-linux-gnu.tar.gz
ENV GROESTLCOIN_URL https://github.com/Groestlcoin/groestlcoin/releases/download/v$GROESTLCOIN_VERSION/$GROESTLCOIN_FILENAME
ENV GROESTLCOIN_SHA256 e90f6ceb56fbc86ae17ee3c5d6d3913c422b7d98aa605226adb669acdf292e9e
ENV GROESTLCOIN_ASC_URL https://github.com/Groestlcoin/groestlcoin/releases/download/v$GROESTLCOIN_VERSION/SHA256SUMS.asc
ENV GROESTLCOIN_PGP_KEY 287AE4CA1187C68C08B49CB2D11BD4F33F1DB499
RUN [ -n "$STANDALONE" ] || \
    (mkdir /opt/groestlcoin && cd /opt/groestlcoin \
    && wget -qO "$GROESTLCOIN_FILENAME" "$GROESTLCOIN_URL" \
    && echo "$GROESTLCOIN_SHA256 $GROESTLCOIN_FILENAME" | sha256sum -c - \
    && for server in $(shuf -e ha.pool.sks-keyservers.net \
                             hkp://p80.pool.sks-keyservers.net:80 \
                             keyserver.ubuntu.com \
                             hkp://keyserver.ubuntu.com:80 \
                             pgp.mit.edu) ; do \
         gpg --batch --keyserver "$server" --recv-keys "$GROESTLCOIN_PGP_KEY" && break || : ; \
       done \
    && wget -qO groestlcoin.asc "$GROESTLCOIN_ASC_URL" \
    && gpg --verify groestlcoin.asc \
    && cat groestlcoin.asc | grep "$GROESTLCOIN_FILENAME" | sha256sum -c - \
    && BD=groestlcoin-$GROESTLCOIN_VERSION/bin \
    && tar -xzvf "$GROESTLCOIN_FILENAME" $BD/groestlcoind $BD/groestlcoin-cli --strip-components=1)

    RUN mkdir /opt/bin && ([ -n "$STANDALONE" ] || \
        (mv /opt/lightningd/cli/lightning-cli /opt/bin/ \
        && mv /opt/lightningd/lightningd/lightning* /opt/bin/ \
        && mv /opt/groestlcoin/bin/* /opt/bin/))

# npm doesn't normally like running as root, allow it since we're in docker
RUN npm config set unsafe-perm true

# Install tini
RUN wget -qO /opt/bin/tini "https://github.com/krallin/tini/releases/download/v0.18.0/tini-amd64" \
    && echo "12d20136605531b09a2c2dac02ccee85e1b874eb322ef6baf7561cd93f93c855 /opt/bin/tini" | sha256sum -c - \
    && chmod +x /opt/bin/tini

# Install Groestlcoin Spark
WORKDIR /opt/spark/client
COPY client/package.json client/npm-shrinkwrap.json ./
COPY client/fonts ./fonts
RUN npm install

WORKDIR /opt/spark
COPY package.json npm-shrinkwrap.json ./
RUN npm install
COPY . .

# Build production NPM package
RUN npm run dist:npm \
 && npm prune --production \
 && find . -mindepth 1 -maxdepth 1 \
           ! -name '*.json' ! -name dist ! -name LICENSE ! -name node_modules ! -name scripts \
           -exec rm -r "{}" \;

# Prepare final image

FROM node:12.16-slim

ARG STANDALONE
ENV STANDALONE=$STANDALONE

WORKDIR /opt/spark

RUN apt-get update && apt-get install -y --no-install-recommends xz-utils inotify-tools netcat-openbsd \
        $([ -n "$STANDALONE" ] || echo libgmp-dev libsqlite3-dev) \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /opt/spark/dist/cli.js /usr/bin/spark-wallet \
    && mkdir /data \
    && ln -s /data/lightning $HOME/.lightning

COPY --from=builder /opt/bin /usr/bin
COPY --from=builder /opt/spark /opt/spark

ENV CONFIG=/data/spark/config TLS_PATH=/data/spark/tls TOR_PATH=/data/spark/tor COOKIE_FILE=/data/spark/cookie HOST=0.0.0.0

# link the granax (Tor Control client) node_modules installation directory
# inside /data/spark/tor/, to persist the Tor Bundle download in the user-mounted volume
RUN ln -s $TOR_PATH/tor-installation/node_modules dist/transport/granax-dep/node_modules

VOLUME /data
ENTRYPOINT [ "tini", "-g", "--", "scripts/docker-entrypoint.sh" ]

EXPOSE 9735 9737
