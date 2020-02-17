#!/bin/bash
set -eo pipefail
trap 'jobs -p | xargs -r kill' SIGTERM

: ${NETWORK:=testnet}
: ${LIGHTNINGD_OPT:=--log-level=debug}
: ${BITCOIND_OPT:=-debug=rpc --printtoconsole=0}

[[ "$NETWORK" == "mainnet" ]] && NETWORK=groestlcoin

if [ -d /etc/lightning ]; then
  echo -n "Using lightningd directory mounted in /etc/lightning... "
  LN_PATH=/etc/lightning
  if [ ! -f $LN_PATH/lightningd.sqlite3 ] && [ -f $LN_PATH/$NETWORK/lightningd.sqlite3 ]; then
    echo -n "Using $LN_PATH/$NETWORK... "
    LN_PATH=$LN_PATH/$NETWORK
  fi
else

  # Setup groestlcoind (only needed when we're starting our own lightningd instance)
  if [ -d /etc/groestlcoin ]; then
    echo -n "Connecting to groestlcoind configured in /etc/groestlcoin... "

    RPC_OPT="-datadir=/etc/groestlcoin $([[ -z "$BITCOIND_RPCCONNECT" ]] || echo "-rpcconnect=$BITCOIND_RPCCONNECT")"

  elif [ -n "$BITCOIND_URI" ]; then
    [[ "$BITCOIND_URI" =~ ^[a-z]+:\/+(([^:/]+):([^@/]+))@([^:/]+:[0-9]+)/?$ ]] || \
      { echo >&2 "ERROR: invalid groestlcoind URI: $BITCOIND_URI"; exit 1; }

    echo -n "Connecting to groestlcoind at ${BASH_REMATCH[4]}... "

    RPC_OPT="-rpcconnect=${BASH_REMATCH[4]}"

    if [ "${BASH_REMATCH[2]}" != "__cookie__" ]; then
      RPC_OPT="$RPC_OPT -rpcuser=${BASH_REMATCH[2]} -rpcpassword=${BASH_REMATCH[3]}"
    else
      RPC_OPT="$RPC_OPT -datadir=/tmp/groestlcoin"
      [[ "$NETWORK" == "groestlcoin" ]] && NET_PATH=/tmp/groestlcoin || NET_PATH=/tmp/groestlcoin/$NETWORK
      mkdir -p $NET_PATH
      echo "${BASH_REMATCH[1]}" > $NET_PATH/.cookie
    fi

  else
    echo -n "Starting groestlcoind... "

    mkdir -p /data/groestlcoin
    RPC_OPT="-datadir=/data/groestlcoin"

    if [ "$NETWORK" != "groestlcoin" ]; then
      BITCOIND_NET_OPT="-$NETWORK"
    fi

    groestlcoind $BITCOIND_NET_OPT $RPC_OPT $BITCOIND_OPT &
    echo -n "waiting for cookie... "
    sed --quiet '/^\.cookie$/ q' <(inotifywait -e create,moved_to --format '%f' -qmr /data/groestlcoin)
  fi

  echo -n "waiting for RPC... "
  groestlcoin-cli $BITCOIND_NET_OPT $RPC_OPT -rpcwait getblockchaininfo > /dev/null
  echo "ready."

  # Setup lightning
  echo -n "Starting lightningd... "

  LN_BASE=/data/lightning
  mkdir -p $LN_BASE

  lnopt=($LIGHTNINGD_OPT --network=$NETWORK --lightning-dir=$LN_BASE --log-file=debug.log)
  [[ -z "$LN_ALIAS" ]] || lnopt+=(--alias="$LN_ALIAS")

  lightningd "${lnopt[@]}" $(echo "$RPC_OPT" | sed -r 's/(^| )-/\1--groestlcoin-/g') > /dev/null &

  LN_PATH=$LN_BASE/$NETWORK
  mkdir -p $LN_PATH
fi

if [ ! -S $LN_PATH/lightning-rpc ] || ! echo | nc -q0 -U $LN_PATH/lightning-rpc; then
  echo -n "waiting for RPC unix socket... "
  sed --quiet '/^lightning-rpc$/ q' <(inotifywait -e create,moved_to --format '%f' -qm $LN_PATH)
fi

# lightning-cli is unavailable in standalone mode, so we can't check the rpc connection.
# Spark itself also checks the connection when starting up, so this is not too bad.
if command -v lightning-cli > /dev/null; then
  # workaround for https://github.com/ElementsProject/lightning/issues/3352
  # (patch is on its way! but this will have to be kept around for v0.8.0 compatibility)
  mkdir -p /tmp/dummy /tmp/dummy/groestlcoin
  lightning-cli --lightning-dir /tmp/dummy --rpc-file $LN_PATH/lightning-rpc getinfo > /dev/null
  echo -n "c-lightning RPC ready."
  rm -r /tmp/dummy
fi

mkdir -p $TOR_PATH/tor-installation/node_modules

if [ -z "$STANDALONE" ]; then
  # when not in standalone mode, run groestlcoin-spark as an additional background job
  echo -e "\nStarting groestlcoin spark..."
  groestlcoin-spark -l $LN_PATH "$@" $SPARK_OPT &

  # shutdown the entire process when any of the background jobs exits (even if successfully)
  wait -n
  kill -TERM $$
else
  # in standalone mode, replace the process with groestlcoin-spark
  echo -e "\nStarting groestlcoin spark (standalone mode)..."
  exec groestlcoin-spark -l $LN_PATH "$@" $SPARK_OPT
fi
