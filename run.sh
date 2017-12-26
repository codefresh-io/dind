#!/bin/sh

DIR=$(dirname $0)

echo "Entering $0 at $(date) "
DIND_VOLUME_STAT_DIR=/var/lib/docker/dind-volume
DIND_VOLUME_CREATED_TS=${DIND_VOLUME_STAT_DIR}/created
DIND_VOLUME_LAST_USED_TS=${DIND_VOLUME_STAT_DIR}/last_used

mkdir -p ${DIND_VOLUME_STAT_DIR}
if [ -f ${DIND_VOLUME_STAT_DIR}/created ]; then
  echo "This is first usage of the dind-volume"
  date +%s > ${DIND_VOLUME_STAT_DIR}/created
fi

date +%%s > ${DIND_VOLUME_STAT_DIR}/last_used
echo "$(hostname) $(date +%%s)" >> ${DIND_VOLUME_STAT_DIR}/pods


sigterm_trap(){
   echo "${1:-SIGTERM} received at $(date)"
   date +%%s > ${DIND_VOLUME_STAT_DIR}/last_used

   echo "Starting Cleaner"
   ${DIR}/clean-docker

   echo "killing MONITOR_PID ${MONITOR_PID}"
   kill $MONITOR_PID

   echo "killing DOCKER_PID ${DOCKER_PID}"
   kill $DOCKER_PID
   sleep 2
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

# Starting monitor
${DIR}/monitor/start.sh  <&- &
MONITOR_PID=$!

# creating daemon json
if [[ ! -f /etc/docker/daemon.json ]]; then
  DAEMON_JSON=${DAEMON_JSON:-default-daemon.json}
  mkdir -p /etc/docker
  cp -v ${DIR}/docker/${DAEMON_JSON} /etc/docker/daemon.json
fi
echo "$(date) - Starting dockerd with /etc/docker/daemon.json: "
cat /etc/docker/daemon.json

dockerd <&- &
while ! test -f /var/run/docker.pid || test -z "$(cat /var/run/docker.pid)"
do
  echo "$(date) - Waiting for docker to start"
  sleep 2
done

DOCKER_PID=$(cat /var/run/docker.pid)
echo "DOCKER_PID = ${DOCKER_PID} "
wait ${DOCKER_PID}

