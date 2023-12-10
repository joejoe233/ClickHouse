#!/bin/bash

# shellcheck disable=SC1091
source /setup_export_logs.sh

# fail on errors, verbose and export all env variables
set -e -x -a

dpkg -i package_folder/clickhouse-common-static_*.deb
dpkg -i package_folder/clickhouse-server_*.deb
dpkg -i package_folder/clickhouse-client_*.deb

# A directory for cache
sudo mkdir /dev/shm/clickhouse
sudo chown clickhouse:clickhouse /dev/shm/clickhouse

sudo clickhouse start

# Wait for the server to start, but not for too long.
for _ in {1..100}
do
    clickhouse-client --query "SELECT 1" && break
    sleep 1
done

setup_logs_replication

# Load the data

clickhouse-client --time < /create.sql

# Run the queries

TRIES=3
QUERY_NUM=1
while read -r query; do
    echo -n "["
    for i in $(seq 1 $TRIES); do
        RES=$(clickhouse-client --time --format Null --query "$query" --progress 0 2>&1 ||:)
        echo -n "${RES}"
        [[ "$i" != "$TRIES" ]] && echo -n ", "

        echo "${QUERY_NUM},${i},${RES}" >> /test_output/test_results.tsv
    done
    echo "],"

    QUERY_NUM=$((QUERY_NUM + 1))
done < /queries.sql

clickhouse-client --query "SELECT total_bytes FROM system.tables WHERE name = 'hits' AND database = 'default'"

echo -e "success\tClickBench finished" > /test_output/check_status.tsv
