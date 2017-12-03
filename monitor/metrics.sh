#!/bin/bash
#
DIR=$(dirname $0)
METRICS_DIR=${DIR}/metrics
METRIC_FILE=${METRICS_DIR}/dind_metrics.prom
METRIC_FILE_TMP=${METRIC_FILE}.$$

COLLECT_INTERVAL=15
DOCKER_VOLUME_DIR=${DOCKER_VOLUME_DIR:-/var/lib/docker}
echo "Started $0 at $(date)
METRIC_FILE=${METRIC_FILE}
DOCKER_VOLUME_DIR=${DOCKER_VOLUME_DIR}
COLLECT_INTERVAL=${COLLECT_INTERVAL}
"

LABELS="dind_name=\"$(hostname)\",volume_path=${DOCKER_VOLUME_DIR}\""
echo "COMMON_LABELS=${LABELS}"

DF_OUT_FILE=/tmp/df.out
DF_INODES_OUT_FILE=/tmp/df-i.out
if [[ $(uname) == "Linux" ]]; then
   DF_OPTS="-B 1024"
fi

while true; do
    df ${DF_OPTS} ${DOCKER_VOLUME_DIR} > ${DF_OUT_FILE}
    df -i ${DOCKER_VOLUME_DIR} > ${DF_INODES_OUT_FILE}

    DOCKER_VOLUME_KB_TOTAL=$(cat ${DF_OUT_FILE} | awk 'NR==2 {print $2}')
    DOCKER_VOLUME_KB_AVAILABLE=$(cat ${DF_OUT_FILE} | awk 'NR==2 {print $4}')
    DOCKER_VOLUME_KB_USAGE=$(cat ${DF_OUT_FILE} | awk 'NR==2 {print $3 / $2}')

    DOCKER_VOLUME_INODES_TOTAL=$(cat ${DF_INODES_OUT_FILE} | awk 'NR==2 {print $2}')
    DOCKER_VOLUME_INODES_AVAILABLE=$(cat ${DF_INODES_OUT_FILE} | awk 'NR==2 {print $4}')
    DOCKER_VOLUME_INODES_USAGE=$(cat ${DF_INODES_OUT_FILE} | awk 'NR==2 {print $3 / $2}')

    cat <<EOF > $METRIC_FILE_TMP
# TYPE docker_volume_size gauge
# HELP total size of docker volume (/var/lib/docker) in kb
docker_volume_kb_total{$LABELS} ${DOCKER_VOLUME_KB_TOTAL}
# TYPE docker_volume_size gauge
# HELP used size of docker volume (/var/lib/docker) in kb
docker_volume_kb_used{$LABELS} ${DOCKER_VOLUME_KB_AVAILABLE}
# TYPE docker_volume_size gauge
# HELP usage of docker volume (/var/lib/docker)
docker_volume_kb_usage{$LABELS} ${DOCKER_VOLUME_KB_USAGE}
# TYPE docker_volume_size gauge
# HELP total inodes of docker volume (/var/lib/docker) in kb
docker_volume_inodes_total{$LABELS} ${DOCKER_VOLUME_INODES_TOTAL}
# HELP available inodes of docker volume (/var/lib/docker) in kb
docker_volume_inodes_total{$LABELS} ${DOCKER_VOLUME_INODES_AVAILABLE}
# HELP inodes usage of docker volume (/var/lib/docker) in kb
docker_volume_inodes_total{$LABELS} ${DOCKER_VOLUME_INODES_USAGE}
EOF

   mv ${METRIC_FILE_TMP} ${METRIC_FILE}
   sleep $COLLECT_INTERVAL
done
