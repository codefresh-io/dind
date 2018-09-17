#!/bin/sh

DIR=$(dirname $0)

echo "Entering $0 at $(date) "
DIND_VOLUME_STAT_DIR=${DIND_VOLUME_STAT_DIR:-/var/lib/docker/dind-volume}
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

   CURRENT_TS=$(date +%s)
   echo ${CURRENT_TS} > ${DIND_VOLUME_LAST_USED_TS_FILE}

   #### Saving Current Docker events
   DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events
   mkdir -p ${DOCKER_EVENTS_DIR}
   DOCKER_EVENTS_FILE="${DOCKER_EVENTS_DIR}"/${CURRENT_TS}
   DOCKER_EVENTS_FORMAT='{{ json . }}'
   echo -e "\nSaving current docker events to ${DOCKER_EVENTS_FILE} "
   docker events --until 0s --format "${DOCKER_EVENTS_FORMAT}" > "${DOCKER_EVENTS_FILE}"

   if [[ -n "${CLEAN_DOCKER}" ]]; then
     echo "Starting Cleaner"
     ${DIR}/cleaner/docker-clean.sh
   fi

   echo "killing MONITOR_PID ${MONITOR_PID}"
   kill $MONITOR_PID

   echo "killing DOCKER_PID ${DOCKER_PID}"
   kill $DOCKER_PID
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
rm -fv /var/run/docker.pid
mkdir -p /var/run/codefresh

# Setup Client certificate ca
if [[ -n "${CODEFRESH_CLIENT_CA_DATA}" ]]; then
  CODEFRESH_CLIENT_CA_FILE=${CODEFRESH_CLIENT_CA_FILE:-/etc/ssl/cf-client/ca.pem}
  mkdir -pv $(dirname ${CODEFRESH_CLIENT_CA_FILE} )
  echo ${CODEFRESH_CLIENT_CA_DATA} | base64 -d >> ${CODEFRESH_CLIENT_CA_FILE}
fi

# creating daemon json
if [[ ! -f /etc/docker/daemon.json ]]; then
  DAEMON_JSON=${DAEMON_JSON:-default-daemon.json}
  mkdir -p /etc/docker
  cp -v ${DIR}/docker/${DAEMON_JSON} /etc/docker/daemon.json
fi
echo "$(date) - Starting dockerd with /etc/docker/daemon.json: "
cat /etc/docker/daemon.json

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

### Trying to start docker
dockerd ${DOCKERD_PARAMS} <&- &
CNT=0
while ! test -f /var/run/docker.pid || test -z "$(cat /var/run/docker.pid)" || ! docker ps
do
  echo "$(date) - Waiting for docker to start"
  sleep 2
done

DOCKER_PID=$(cat /var/run/docker.pid)
echo "DOCKER_PID = ${DOCKER_PID} "
wait ${DOCKER_PID}

