#!/bin/bash
#
DIR=$(dirname $0)
METRICS_DIR=${DIR}/metrics
METRIC_FILE=${METRICS_DIR}/dind_metrics.prom
METRIC_FILE_TMP=${METRIC_FILE}.$$

COLLECT_INTERVAL=15
DOCKERD_DATA_ROOT=${DOCKERD_DATA_ROOT:-/var/lib/docker}

DIND_VOLUME_STAT_DIR=${DIND_VOLUME_STAT_DIR:-${DOCKERD_DATA_ROOT}/dind-volume}
mkdir -p ${DIND_VOLUME_STAT_DIR}

LAST_CLEANED_TS_FILE=${DIND_VOLUME_STAT_DIR}/last_cleaned_ts
LAST_PRUNED_TS_FILE=${DIND_VOLUME_STAT_DIR}/last_pruned_ts

echo "Started $0 at $(date)
METRIC_FILE=${METRIC_FILE}
DOCKERD_DATA_ROOT=${DOCKERD_DATA_ROOT}
COLLECT_INTERVAL=${COLLECT_INTERVAL}
"

LABELS="dind_pod_name=\"$(hostname)\",data_root_path=\"${DOCKERD_DATA_ROOT}\""
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

    df ${DF_OPTS} ${DOCKERD_DATA_ROOT} > ${DF_OUT_FILE}
    df -i ${DOCKERD_DATA_ROOT} > ${DF_INODES_OUT_FILE}

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

  ## Metrics for last cleaned and last_pruned ts
  if [[ -f ${LAST_CLEANED_TS_FILE} ]]; then
     DOCKER_VOLUME_LAST_CLEANED_TS=$(cat ${LAST_CLEANED_TS_FILE})
     cat <<EOF >> $METRIC_FILE_TMP
# TYPE docker_volume_last_cleaned_ts gauge
# HELP docker_volume_last_cleaned_ts volume last cleaned by docker-clean.sh timestamp
docker_volume_last_cleaned_ts{$LABELS} ${DOCKER_VOLUME_LAST_CLEANED_TS}

EOF
  fi

  if [[ -f ${LAST_PRUNED_TS_FILE} ]]; then
     DOCKER_VOLUME_LAST_PRUNED_TS=$(cat ${LAST_PRUNED_TS_FILE})
     cat <<EOF >> $METRIC_FILE_TMP
# TYPE docker_volume_last_pruned_ts gauge
# HELP docker_volume_last_pruned_ts volume last pruned by docker-clean.sh timestamp
docker_volume_last_pruned_ts{$LABELS} ${DOCKER_VOLUME_LAST_PRUNED_TS}

EOF
  fi
  
  mv ${METRIC_FILE_TMP} ${METRIC_FILE}
  sleep $COLLECT_INTERVAL
done
