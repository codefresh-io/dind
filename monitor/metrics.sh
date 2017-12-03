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

LABELS="dind_name=\"$(hostname)\",volume_path=\"${DOCKER_VOLUME_DIR}\""
echo "COMMON_LABELS=${LABELS}"

DOCKER_PS_OUT_FILE=/tmp/docker-ps.out

DF_OUT_FILE=/tmp/df.out
DF_INODES_OUT_FILE=/tmp/df-i.out
if [[ $(uname) == "Linux" ]]; then
   DF_OPTS="-B 1024"
fi

while true; do
    # Checking if docker is up
    docker ps -q > ${DOCKER_PS_OUT_FILE}
    if [[ $? == 0 ]]; then
      DOCKER_UP=1
      DOCKER_CONTAINERS_COUNT=$(wc -l < ${DOCKER_PS_OUT_FILE})
    else
      DOCKER_UP=0
      DOCKER_CONTAINERS_COUNT=0
    fi

    df ${DF_OPTS} ${DOCKER_VOLUME_DIR} > ${DF_OUT_FILE}
    df -i ${DOCKER_VOLUME_DIR} > ${DF_INODES_OUT_FILE}

    DOCKER_VOLUME_KB_TOTAL=$(cat ${DF_OUT_FILE} | awk 'NR==2 {print $2}')
    DOCKER_VOLUME_KB_AVAILABLE=$(cat ${DF_OUT_FILE} | awk 'NR==2 {print $4}')
    DOCKER_VOLUME_KB_USAGE=$(cat ${DF_OUT_FILE} | awk 'NR==2 {print $3 / $2}')

    DOCKER_VOLUME_INODES_TOTAL=$(cat ${DF_INODES_OUT_FILE} | awk 'NR==2 {print $2}')
    DOCKER_VOLUME_INODES_AVAILABLE=$(cat ${DF_INODES_OUT_FILE} | awk 'NR==2 {print $4}')
    DOCKER_VOLUME_INODES_USAGE=$(cat ${DF_INODES_OUT_FILE} | awk 'NR==2 {print $3 / $2}')

    cat <<EOF > $METRIC_FILE_TMP
# TYPE docker_up gauge
# HELP docker_up - docker daemon is running
docker_up{$LABELS} ${DOCKER_UP}

# TYPE docker_containers_count gauge
# HELP docker_containers_count - docker daemon is running
docker_containers_count{$LABELS} ${DOCKER_CONTAINERS_COUNT}

# TYPE docker_volume_kb_total gauge
# HELP docker_volume_kb_total - total size in kb docker volume (/var/lib/docker)
docker_volume_kb_total{$LABELS} ${DOCKER_VOLUME_KB_TOTAL}

# TYPE docker_volume_kb_available gauge
# HELP docker_volume_kb_available - available size in kb docker volume (/var/lib/docker)
docker_volume_kb_available{$LABELS} ${DOCKER_VOLUME_KB_AVAILABLE}

# TYPE docker_volume_kb_usage gauge
# HELP docker_volume_kb_usage - usage (used/total) of docker volume (/var/lib/docker)
docker_volume_kb_usage{$LABELS} ${DOCKER_VOLUME_KB_USAGE}

# TYPE docker_volume_inodes_total gauge
# HELP docker_volume_inodes_total - total inodes in docker volume (/var/lib/docker)
docker_volume_inodes_total{$LABELS} ${DOCKER_VOLUME_INODES_TOTAL}

# TYPE docker_volume_inodes_available gauge
# HELP docker_volume_inodes_available - available inodes in docker volume (/var/lib/docker)
docker_volume_inodes_available{$LABELS} ${DOCKER_VOLUME_INODES_AVAILABLE}

# TYPE docker_volume_inodes_usage gauge
# HELP docker_volume_inodes_usage - usage (used/total)  of inodes in docker volume (/var/lib/docker)
docker_volume_inodes_usage{$LABELS} ${DOCKER_VOLUME_INODES_USAGE}

EOF

   mv ${METRIC_FILE_TMP} ${METRIC_FILE}
   sleep $COLLECT_INTERVAL
done
