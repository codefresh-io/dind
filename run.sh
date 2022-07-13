#!/bin/bash

DIR=$(dirname $0)

echo "Entering $0 at $(date) "
DOCKERD_DATA_ROOT=${DOCKERD_DATA_ROOT:-/home/rootless/.local/share/docker}
DIND_VOLUME_STAT_DIR=${DIND_VOLUME_STAT_DIR:-${DOCKERD_DATA_ROOT}/dind-volume}
DIND_VOLUME_CREATED_TS_FILE=${DIND_VOLUME_STAT_DIR}/created
DIND_VOLUME_LAST_USED_TS_FILE=${DIND_VOLUME_STAT_DIR}/last_used
DIND_VOLUME_USED_BY_PODS_FILE=${DIND_VOLUME_STAT_DIR}/pods

DIND_IMAGES_LIB_DIR=${DIND_IMAGES_LIB_DIR:-"/opt/codefresh/dind/images-libs"}



mkdir -p ${DIND_VOLUME_STAT_DIR}
if [ ! -f ${DIND_VOLUME_STAT_DIR}/created ]; then
  echo "This is first usage of the dind-volume"
  date +%s > ${DIND_VOLUME_CREATED_TS_FILE}
fi

CURRENT_TS=$(date +%s)
echo ${CURRENT_TS} > ${DIND_VOLUME_LAST_USED_TS_FILE}

export POD_NAME=${POD_NAME:-$(hostname)}
echo "${POD_NAME} ${CURRENT_TS}" >> ${DIND_VOLUME_USED_BY_PODS_FILE}

sigterm_trap(){
   echo "${1:-SIGTERM} received at $(date)"
   export SIGTERM=1
   CURRENT_TS=$(date +%s)
   echo ${CURRENT_TS} > ${DIND_VOLUME_LAST_USED_TS_FILE}

   #### Saving Current Docker events
   DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events
   mkdir -p ${DOCKER_EVENTS_DIR}
   DOCKER_EVENTS_FILE="${DOCKER_EVENTS_DIR}"/${CURRENT_TS}
   DOCKER_EVENTS_FORMAT='{{ json . }}'
   echo -e "\nSaving current docker events to ${DOCKER_EVENTS_FILE} "
   docker events --until 0s --format "${DOCKER_EVENTS_FORMAT}" > "${DOCKER_EVENTS_FILE}"

   if [[ -n "${CLEANER_AGENT_PID}" ]]; then
      echo "killing CLEANER_AGENT_PID ${CLEANER_AGENT_PID}"
      kill $CLEANER_AGENT_PID
   fi

   if [[ -n "${CLEAN_DOCKER}" ]]; then
     echo "Starting Cleaner"
     ${DIR}/cleaner/docker-clean.sh
   fi
   
   echo "Cleaning old events files"
   find ${DOCKER_EVENTS_DIR} -type f -mtime +10 -exec rm -fv {} \;

   echo "killing MONITOR_PID ${MONITOR_PID}"
   kill $MONITOR_PID

   echo "killing DOCKERD_PID ${DOCKERD_PID}"
   kill $DOCKERD_PID
   sleep 2

   if [[ -n "${USE_DIND_IMAGES_LIB}" && "${USE_DIND_IMAGES_LIB}" != "false" && -n "${DOCKERD_DATA_ROOT}" ]]; then
     echo "We used DIND_IMAGES_LIB directory, removing DOCKERD_DATA_ROOT = ${DOCKERD_DATA_ROOT}"
     time rm -rf ${DOCKERD_DATA_ROOT}
   fi

   echo "Running processes: "
   ps -ef
   echo "Exiting at $(date) "
}
trap sigterm_trap SIGTERM SIGINT

# Starting run daemon
rm -fv /run/user/1000/docker.pid
mkdir -p /var/run/codefresh

# Setup Client certificate ca
if [[ -n "${CODEFRESH_CLIENT_CA_DATA}" ]]; then
  CODEFRESH_CLIENT_CA_FILE=${CODEFRESH_CLIENT_CA_FILE:-/etc/ssl/cf-client/ca.pem}
  mkdir -pv $(dirname ${CODEFRESH_CLIENT_CA_FILE} )
  echo ${CODEFRESH_CLIENT_CA_DATA} | base64 -d >> ${CODEFRESH_CLIENT_CA_FILE}
fi

# creating daemon json
if [[ ! -f ~/.config/docker/daemon.json ]]; then
  DAEMON_JSON=${DAEMON_JSON:-default-daemon.json}
  mkdir -p ~/.config/docker
  cp -v ${DIR}/docker/${DAEMON_JSON} ~/.config/docker/daemon.json
fi
echo "$(date) - Starting dockerd with ~/.config/docker/daemon.json: "
cat ~/.config/docker/daemon.json

# Docker registry self-signed Certs - workaround for problem where kubernetes cannot mount 
# for cc in $(find ~/.config/docker/certs.d -type d -maxdepth 1)
# do
#   echo "Trying to process Registery Self-Signed certs dir $cc "
#   ls -l "${cc}"
#   NEW_CERTS_DIR=$(echo $cc | sed -E 's/(.*)_([0-9]+)/\1\:\2/g')

#   if [[ "${cc}" != "${NEW_CERTS_DIR}" ]]; then
#     echo "Creating Registry Registery Self-Signed certs dir ${NEW_CERTS_DIR}"
#     mkdir -pv "${NEW_CERTS_DIR}"
#     cp -vrfL "${cc}"/{ca.crt,client.key,client.cert} "${NEW_CERTS_DIR}"/
#   fi
# done

#DOCKERD_PARAMS=""
if [[ -n "${USE_DIND_IMAGES_LIB}" && "${USE_DIND_IMAGES_LIB}" != "false" ]]; then
   mkdir -p ${DIND_IMAGES_LIB_DIR}/../pods
   DOCKERD_DATA_ROOT=$(realpath ${DIND_IMAGES_LIB_DIR}/..)/pods/${POD_NAME}
   echo "USE_DIND_IMAGES_LIB is set - using --data-root ${DOCKERD_DATA_ROOT} "
   # looking for first available
   for ii in $(find ${DIND_IMAGES_LIB_DIR} -mindepth 1 -maxdepth 1 -type d | grep -E 'lib-[[:digit:]]{1,3}$')
   do
     echo "Trying to use image-lib-dir $ii ... "
     [[ -d "${DOCKERD_DATA_ROOT}" ]] && rm -rf "${DOCKERD_DATA_ROOT}"
     mv $ii "${DOCKERD_DATA_ROOT}" && \
     DOCKERD_PARAMS="${DOCKERD_PARAMS} --data-root ${DOCKERD_DATA_ROOT}" && \
     export DOCKERD_DATA_ROOT && \
     echo "Successfully moved ${ii} to ${DOCKERD_DATA_ROOT} " && \
     break
   done
fi
echo "DOCKERD_PARAMS = ${DOCKERD_PARAMS}"

# Starting monitor
${DIR}/monitor/start.sh  <&- &
MONITOR_PID=$!

### start docker with retry
DOCKERD_PID_FILE=/run/user/1000/docker.pid
DOCKERD_PID_MAXWAIT=${DOCKERD_PID_MAXWAIT:-20}
DOCKERD_LOCK_MAXWAIT=${DOCKERD_LOCK_MAXWAIT:-60}
DOCKER_UP_MAXWAIT=${DOCKERD_UP_MAXWAIT:-90}
while true
do
  [[ -n "${SIGTERM}" ]] && break
  echo "Starting docker ..."
  if [[ -f ${DOCKERD_PID_FILE} ]] || pgrep -l dockerd ; then
      DOCKERD_PID=$(cat ${DOCKERD_PID_FILE})
      echo "  Waiting for dockerd pid ${DOCKERD_PID_FILE} to exit ..."
      CNT=0
      pkill dockerd 
      while pgrep -l dockerd
      do
        [[ -n "${SIGTERM}" ]] && break 2
        (( CNT++ ))
        echo ".... old dockerd is still running - $(date)"
        if [[ ${CNT} -ge 120 ]]; then
          echo "Killing old dockerd"
          pkill -9 dockerd
          break
        fi
        sleep 1
      done
      rm -fv ${DOCKERD_PID_FILE}
  fi

  echo "$(date) - Checking if other dockerd running on same /home/rootless/.local/share/docker by check locks on containerd/daemon/io.containerd.metadata.v1.bolt/meta.db "
  CONTEINERD_DB=${DOCKERD_DATA_ROOT}/containerd/daemon/io.containerd.metadata.v1.bolt/meta.db
  if [[ -f ${CONTEINERD_DB} ]]; then
    echo "Checking if another dockerd is running on same ${DOCKERD_DATA_ROOT} boltdb $CONTEINERD_DB is locked"
    CNT=0
    while ! bolter --file ${CONTEINERD_DB}
    do
      [[ -n "${SIGTERM}" ]] && break 2
      echo "$(date) - Waiting for containerd boltd ${CONTEINERD_DB}"
      (( CNT++ ))
      if (( CNT > ${DOCKERD_LOCK_MAXWAIT} )); then
        echo "  giving up and trying to start docker anyway Waited more than ${DOCKERD_LOCK_MAXWAIT}s for containerd boltdb unlock"
        break
      fi
      sleep 1
    done
  else 
    echo "containerd db is not locked"
  fi

  echo "Starting dockerd"
  #dockerd ${DOCKERD_PARAMS} <&- &
  ${DIR}/cf-dockerd-entrypoint.sh dockerd ${DOCKERD_PARAMS} <&- &

  echo "Waiting at most 20s for docker pid"
  CNT=0
  while ! test -f "${DOCKERD_PID_FILE}" || test -z "$(cat ${DOCKERD_PID_FILE})"
  do
    [[ -n "${SIGTERM}" ]] && break 2
    echo "$(date) - Waiting for docker pid file ${DOCKERD_PID_FILE}"
    (( CNT++ ))
    if (( CNT > ${DOCKERD_PID_MAXWAIT} )); then
      echo "Waited more than ${DOCKERD_PID_MAXWAIT}s for docker pid, retry dockerd start"
      continue 2
    fi
    sleep 1
  done

  export DOCKER_HOST='unix:///run/user/1000/docker.sock'
  echo "Waiting at most 2m for docker pid"
  CNT=0
  while ! docker ps
  do
    [[ -n "${SIGTERM}" ]] && break 2
    echo "$(date) - Waiting for docker running by check docker ps "
    (( CNT++ ))
    if (( CNT > ${DOCKER_UP_MAXWAIT} )); then
      echo "Waited more than ${DOCKER_UP_MAXWAIT}s for dockerd, retry dockerd start"
      continue 2
    fi
    sleep 1
  done
  echo "$(date) - dockerd has been started"
  break
done

# Starting cleaner agent
if [[ -z "${DISABLE_CLEANER_AGENT}" && -z "${SIGTERM}" ]]; then
  ${DIR}/cleaner/cleaner-agent.sh  <&- &
  CLEANER_AGENT_PID=$!
fi

DOCKERD_PID=$(cat /run/user/1000/docker.pid)
echo "DOCKERD_PID = ${DOCKERD_PID} "
wait ${DOCKERD_PID}
