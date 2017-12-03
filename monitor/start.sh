#!/bin/bash

echo "Starting dind monitoring:
node_exporter and metric collector in background
"

DIR=$(dirname $0)

LOG_DIR=${DIR}/log
mkdir -p ${LOG_DIR}

NODE_EXPORTER_LOG_FILE=${LOG_DIR}/node_exporter.log
echo "Starting node_exporter.sh in background, log file in $NODE_EXPORTER_LOG_FILE "
${DIR}/node_exporter.sh &>"${NODE_EXPORTER_LOG_FILE}" <&- &


METRICS_LOG_FILE=${LOG_DIR}/metrics.log
echo "Starting metrics.sh in background, log file in $METRICS_LOG_FILE "
${DIR}/metrics.sh &>"${METRICS_LOG_FILE}" <&- &