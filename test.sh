#!/bin/bash

echo -e "mysql_test start\n"

# `set -eu` prevent referencing an var before setting it, so we set the env vars here
TIDB_TEST_STORE_NAME=$TIDB_TEST_STORE_NAME
TIKV_PATH=$TIKV_PATH

CACHE_ENABLED=$CACHE_ENABLED

normal_config="config.toml"
prepare_cache_config="config-ps-cache.toml"

mysql_test_log="./mysql-test.out"
record=0
record_case=""
TEST_BIN_PATH=./mysql_test

if [[ $CACHE_ENABLED -eq 1 ]];then
    echo -e "CACHE_ENABLED"
    TIDB_CONFIG=$prepare_cache_config
fi

if [[ -z "${TIDB_CONFIG}" || ! -e ${TIDB_CONFIG} ]]; then
    TIDB_CONFIG="./config.toml"
fi

set -eu

rm -rf "$mysql_test_log"


./build.sh

if [[ -z $TIDB_SERVER_PATH || ! -e $TIDB_SERVER_PATH ]]; then
    echo -e "no tidb-server was found, build from source code"
    # This is likely to be failed, depending on whether tidb parser is well set up
    GO111MODULE=on go build -race -o mysql_test_tidb-server github.com/pingcap/tidb/tidb-server
    TIDB_SERVER_PATH=./mysql_test_tidb-server
fi

echo "start tidb-server, log file: $mysql_test_log"
if [[ $TIDB_TEST_STORE_NAME = tikv ]]; then
    "$TIDB_SERVER_PATH" -config "$TIDB_CONFIG" -store tikv -path "$TIKV_PATH" > "$mysql_test_log" 2>&1 &
    SERVER_PID=$!
else
    "$TIDB_SERVER_PATH" -config "$TIDB_CONFIG" -store unistore -path "" -lease 0s > "$mysql_test_log" 2>&1 &
    SERVER_PID=$!
fi
echo "tidb-server(PID: $SERVER_PID) started"
trap 'echo "tidb-server(PID: $SERVER_PID) stopped"; kill -9 "$SERVER_PID" || true' EXIT

sleep 5

echo "run all mysql test cases"
if [[ $record -eq 1 ]]; then
    echo "record result for case: $record_case"
    "$TEST_BIN_PATH" --port=4001 --log-level=error --all=true --record "$record_case"
else
    "$TEST_BIN_PATH" --port=4001 --log-level=error --all=true
fi

race=$(grep 'DATA RACE' "$mysql_test_log" || true)
if [[ -n $race ]]; then
    echo "tidb-server DATA RACE!"
    cat "$mysql_test_log"
    exit 1
fi
echo "mysqltest end"
