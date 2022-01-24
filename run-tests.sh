#!/bin/bash

# `set -eu` prevent referencing an var before setting it, so we set the env vars here
TIDB_TEST_STORE_NAME=$TIDB_TEST_STORE_NAME
TIKV_PATH=$TIKV_PATH

build=1
mysql_test="./mysql_test"
tidb_server=""
mysql_test_log="./mysql-test.out"
tests=()
record=0
record_case=""
default_prepare_cache_test=("ps")
normal_config="config.toml"
prepare_cache_config="config-ps-cache.toml"
config=$normal_config
cache_enabled=0

set -eu

function help_message()
{
    echo "Usage: $0 [options]

    -h: Print this help message.

    -c <y|Y|n|N>: run tests with prepare cache enabled if \"y\" or \"Y\". [default \"n\" if this option is not specified].

    -s <tidb-server-path>: Use tidb-server in <tidb-server-path> for testing.

    -b <y|Y|n|N>: \"y\" or \"Y\" for building test binaries [default \"y\" if this option is not specified].
                  \"n\" or \"N\" for not to build.
                  The building of tidb-server will be skiped if \"-s <tidb-server-path>\" is provided.

    -r <test-name>: Run tests in file \"t/<test-name>.test\" and record result to file \"r/<test-name>.result\".
                    \"all\" for running all tests and record their results.

    -t <test-name>: Run tests in file \"t/<test-name>.test\".
                    This option will be ignored if \"-r <test-name>\" is provided.
"
}

function build_tidb_server()
{
    tidb_server="./mysqltest_tidb-server"
    echo "building tidb-server binary: $tidb_server"
    rm -rf "$tidb_server"
    GO111MODULE=on go build -race -o "$tidb_server" github.com/pingcap/tidb/tidb-server
}

function build_mysql_test()
{
    echo "building mysql-test binary: $mysql_test"
    rm -rf "$mysql_test"
    ./build.sh
}

while getopts "t:s:r:b:c:v:h" opt; do
    case $opt in
        t)
            tests+=($OPTARG)
            ;;
        s)
            tidb_server=$OPTARG
            ;;
        r)
            record=1
            record_case=$OPTARG
            ;;
        b)
            case $OPTARG in
                y|Y)
                    build=1
                    ;;
                n|N)
                    build=0
                    ;;
                *)
                    help_messge 1>&2
                    exit 1
                    ;;
            esac
            ;;
	c)
            case $OPTARG in
                y|Y)
                    cache_enabled=1
                    ;;
                n|N)
                    cache_enabled=0
                    ;;
                *)
                    help_messge 1>&2
                    exit 1
                    ;;
            esac
            ;;
        h)
            help_message
            exit 0
            ;;
        *)
            help_message 1>&2
            exit 1
            ;;
    esac
done

if [[ $cache_enabled -eq 1 ]]; then
    config=$prepare_cache_config
    if [[ ${#tests[@]} -eq 0 ]]; then
        tests=(${default_prepare_cache_test[@]})
    fi
fi

if [[ $build -eq 1 ]]; then
    if [[ -z $tidb_server ]]; then
        build_tidb_server
    else
        echo "skip building tidb-server, using existing binary: $tidb_server"
    fi
    build_mysql_test
else
    if [[ -z $tidb_server ]]; then
        tidb_server="./mysqltest_tidb-server"
    fi
    if [[ -z $mysql_test ]]; then
        mysql_test="./mysql_test"
    fi
    echo "skip building tidb-server, using existing binary: $tidb_server"
    echo "skip building mysqltest, using existing binary: $mysql_test"
fi

rm -rf "$mysql_test_log"

echo "start tidb-server, log file: $mysql_test_log"
if [[ $TIDB_TEST_STORE_NAME = tikv ]]; then
    "$tidb_server" -config "$config" -store tikv -path "$TIKV_PATH" > "$mysql_test_log" 2>&1 &
    server_pid=$!
else
    "$tidb_server" -config "$config" -store unistore -path "" -lease 0s > "$mysql_test_log" 2>&1 &
    server_pid=$!
fi
echo "tidb-server(PID: $server_pid) started"
trap 'echo "tidb-server(PID: $server_pid) stopped"; kill -9 "$server_pid" || true' EXIT

sleep 5

if [[ $record -eq 1 ]]; then
    if [[ $record_case = 'all' ]]; then
        echo "record resut for all cases"
        "$mysql_test" --port=4001 --record=true --log-level=error
    else
        echo "record result for case: \"$record_case\""
        "$mysql_test" --port=4001 --log-level=error --record "$record_case"
    fi
else
    if [[ ${#tests[@]} -eq 0 ]]; then
        echo "run all mysql test cases"
        "$mysql_test" --port=4001 --log-level=error
    else
        echo "run mysql test cases: ${tests[*]}"
        "$mysql_test" --port=4001 --log-level=error "${tests[@]}"
    fi
fi

race=$(grep 'DATA RACE' "$mysql_test_log" || true)
if [[ -n $race ]]; then
    echo "tidb-server DATA RACE!"
    cat "$mysql_test_log"
    exit 1
fi
echo "mysqltest end"
