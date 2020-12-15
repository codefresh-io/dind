#!/bin/bash
#

DIR=$(dirname $0)
TEXTFILE_DIRECTORY=${DIR}/metrics
mkdir -p ${TEXTFILE_DIRECTORY}
echo "Starting node_exporter at $(date):
   TEXTFILE_DIRECTORY = ${TEXTFILE_DIRECTORY}
"

ENABLED_COLLECTORS=${ENABLED_COLLECTORS//,/ }
ENABLED_COLLECTORS_ARRAY=($ENABLED_COLLECTORS)

ENABLE_COLLECTORS_ARGS=""
for i in ${ENABLED_COLLECTORS_ARRAY[@]}; do
   echo "node_exporter - Enabling collector $i "
   ENABLE_COLLECTORS_ARGS="${ENABLE_COLLECTORS_ARGS} --collector.${i}"
done

node_exporter --collector.disable-defaults ${ENABLE_COLLECTORS_ARGS} --collector.textfile --collector.textfile.directory=${TEXTFILE_DIRECTORY}
