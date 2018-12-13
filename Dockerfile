FROM node:8.11-slim as builder

ARG DEVELOPER
ARG STANDALONE=1
ENV STANDALONE=$STANDALONE

# Install build c-lightning for third-party packages (c-lightning/groestlcoind)
RUN apt-get update && apt-get install -y --no-install-recommends git \
    $([ -n "$STANDALONE" ] || echo "autoconf automake build-essential git libtool libgmp-dev \
                                     libsqlite3-dev python python3 wget zlib1g-dev")

ARG LIGHTNINGD_VERSION=6417fce159b70bc4cb61b024bd9d36b9b8f3ef8d 

RUN [ -n "$STANDALONE" ] || ( \
    git clone https://github.com/Groestlcoin/lightning.git /opt/lightningd \
    && cd /opt/lightningd \
    && git checkout $LIGHTNINGD_VERSION \
    && DEVELOPER=$DEVELOPER ./configure \
    && make)

# Install groestlcoind

ENV GROESTLCOIN_VERSION 2.16.3
ENV GROESTLCOIN_URL https://github.com/Groestlcoin/groestlcoin/releases/download/v2.16.3/groestlcoin-2.16.3-x86_64-linux-gnu.tar.gz
ENV GROESTLCOIN_SHA256 f15bd5e38b25a103821f1563cd0e1b2cf7146ec9f9835493a30bd57313d3b86f

RUN mkdir /opt/groestlcoin && cd /opt/groestlcoin \
    && wget -qO groestlcoin.tar.gz "$GROESTLCOIN_URL" \
    && echo "$GROESTLCOIN_SHA256  groestlcoin.tar.gz" | sha256sum -c - \
    && tar -xzvf groestlcoin.tar.gz groestlcoin-cli --exclude=*-qt \
    && rm groestlcoin.tar.gz

    RUN mkdir /opt/bin && ([ -n "$STANDALONE" ] || \
        (mv /opt/lightningd/cli/lightning-cli /opt/bin/ \
        && mv /opt/lightningd/lightningd/lightning* /opt/bin/ \
        && mv /opt/groestlcoin/bin/* /opt/bin/))

# npm doesn't normally like running as root, allow it since we're in docker
RUN npm config set unsafe-perm true

# Install Spark
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

FROM node:8.11-slim

ARG STANDALONE
ENV STANDALONE=$STANDALONE

WORKDIR /opt/spark

RUN ([ -n "$STANDALONE" ] || ( \
          apt-get update && apt-get install -y --no-install-recommends inotify-tools libgmp-dev libsqlite3-dev xz-utils)) \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /opt/spark/dist/cli.js /usr/bin/spark-wallet \
    && mkdir /data \
    && ln -s /data/lightning $HOME/.lightning

COPY --from=builder /opt/bin /usr/bin
COPY --from=builder /opt/spark /opt/spark

ENV CONFIG=/data/spark/config TLS_PATH=/data/spark/tls TOR_PATH=/data/spark/tor HOST=0.0.0.0

# link the hsv3 (Tor Hidden Service V3) node_modules installation directory
# inside /data/spark/tor/, to persist the Tor Bundle download in the user-mounted volume
RUN ln -s $TOR_PATH/tor-installation/node_modules dist/transport/hsv3-dep/node_modules

VOLUME /data
ENTRYPOINT [ "scripts/docker-entrypoint.sh" ]

EXPOSE 9735 9737
