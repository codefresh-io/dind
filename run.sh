#!/bin/sh

DIR=$(dirname $0)

# Adding cleaner
if [[ -n "${DOCKER_CLEANER_CRON}" ]]; then
  echo "${DOCKER_CLEANER_CRON} $(realpath $(dirname $0)/docker-cleaner.sh) " | tee -a /etc/crontabs/root
  crond
fi

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
  cp -v ${DIR}/docker/${DAEMON_JSON} /etc/docker/daemon.json
fi
echo "$(date) - Starting dockerd with /etc/docker/daemon.json: "
cat /etc/docker/daemon.json

dockerd