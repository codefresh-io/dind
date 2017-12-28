#!/bin/bash
#
# Cleaning dind
# see README.md for details
#
echo "Entering $0 at $(date) "

CLEAN_PERIOD_SECONDS=${CLEAN_PERIOD_SECONDS:-21600} # 6 hours
CLEAN_PERIOD_BUILDS=${CLEAN_PERIOD_BUILDS:-10}

IMAGE_RETAIN_PERIOD=${IMAGE_RETAIN_PERIOD:-259200}
VOLUMES_RETAIN_PERIOD=${VOLUMES_RETAIN_PERIOD:-259200}
echo "
CLEAN_PERIOD_SECONDS=${CLEAN_PERIOD_SECONDS}
CLEAN_PERIOD_BUILDS=${CLEAN_PERIOD_BUILDS}
IMAGE_RETAIN_PERIOD=${IMAGE_RETAIN_PERIOD}
VOLUMES_RETAIN_PERIOD=${VOLUMES_RETAIN_PERIOD}
DRY_RUN=${DRY_RUN}
"

#### Defining DIND_VOLUME_STAT dir and stat files
DOCKER_VOLUME_DIR=${DOCKER_VOLUME_DIR:-/var/lib/docker}
DIND_VOLUME_STAT_DIR=${DIND_VOLUME_STAT_DIR:-${DOCKER_VOLUME_DIR}/dind-volume}
mkdir -p ${DIND_VOLUME_STAT_DIR}

LAST_CLEANED_TS_FILE=${DIND_VOLUME_STAT_DIR}/last_cleaned_ts
LAST_CLEANED_POD_FILE=${DIND_VOLUME_STAT_DIR}/last_cleaned_pod
DIND_VOLUME_USED_BY_PODS_FILE=${DIND_VOLUME_STAT_DIR}/pods

POD_NAME=${POD_NAME:-$(hostname)}
CURRENT_TS=$(date %+s)

#### Current Docker events
#DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events
#DOCKER_EVENTS_FILE="${DOCKER_EVENTS_DIR}"/${CURRENT_TS}
#DOCKER_EVENTS_FORMAT='{{ json . }}'
#echo -e "\nSaving current docker events to ${DOCKER_EVENTS_FILE} "
#docker events --until 0s --format "${DOCKER_EVENTS_FORMAT}" > "${DOCKER_EVENTS_FILE}"

#### Checking if we need to clean by dind stat
NEED_TO_CLEEN=""

echo -e "\nChecking if  need to clean by last cleaned date - CLEAN_PERIOD_SECONDS=${CLEAN_PERIOD_SECONDS}"
if [[ ! -f "${LAST_CLEANED_TS_FILE}" ]]; then
  echo "First launch of dind cleaner - ${LAST_CLEANED_TS_FILE} file does not exist. Creating"
  echo ${CURRENT_TS} > "${LAST_CLEANED_TS_FILE}"
else

  LAST_CLEANED_TS=$(cat ${LAST_CLEANED_TS_FILE})
  LAST_CLEANED_SECONDS_AGO=$(( CURRENT_TS - LAST_CLEANED_TS ))
  echo "LAST_CLEANED_TS = ${LAST_CLEANED_TS} , LAST_CLEANED_SECONDS_AGO = ${LAST_CLEANED_SECONDS_AGO} vs CLEAN_PERIOD_SECONDS = ${CLEAN_PERIOD_SECONDS} "
  if [[ ${LAST_CLEANED_SECONDS_AGO} -ge ${CLEAN_PERIOD_SECONDS} ]]; then
    echo "NEED TO CLEAN: Volume was last cleaned ${LAST_CLEANED_SECONDS_AGO} seconds ago"
    NEED_TO_CLEEN=1
  fi
fi

echo -e "\nChecking if  need to clean by last cleaned pod - CLEAN_PERIOD_BUILDS=${CLEAN_PERIOD_BUILDS}"
if [[ ! -f "${LAST_CLEANED_POD_FILE}" ]]; then
  echo "First launch of dind cleaner - ${LAST_CLEANED_POD_FILE} file does not exist. Creating"
  echo ${POD_NAME} > "${LAST_CLEANED_POD_FILE}"
else
  LAST_CLEANED_POD_NAME=$(cat ${LAST_CLEANED_POD_FILE})
  LAST_CLEANED_POD_LINE_GREP=$(grep -n "${DIND_VOLUME_USED_BY_PODS_FILE}" )
  THIS_POD_LINE_GREP=$(grep -n "${DIND_VOLUME_USED_BY_PODS_FILE}" )
  if [[ -n "${LAST_CLEANED_POD_LINE_GREP}" && -n "${THIS_POD_LINE_GREP}" ]]; then
    LAST_CLEANED_POD_LINE=$(echo "${LAST_CLEANED_POD_LINE_GREP}" | cut -d":" -f1)
    THIS_POD_LINE=$(echo "${THIS_POD_LINE_GREP}" | cut -d":" -f1)
    LAST_CLEANED_BUILDS_AGO=$(( CURRENT_TS - LAST_CLEANED_TS ))
    if [[ ${LAST_CLEANED_BUILDS_AGO} -ge ${CLEAN_PERIOD_BUILDS} ]]; then
        echo "NEED TO CLEAN: Volume was last cleaned ${LAST_CLEANED_BUILDS_AGO} builds ago"
        NEED_TO_CLEEN=1
    fi
  fi
fi

if [[ -z "${NEED_TO_CLEEN}" ]]; then
  echo "NO need to clean, EXITING: it is new volume or it was cleaned less than ${CLEAN_PERIOD_SECONDS} ago it was cleaned less than ${CLEAN_PERIOD_BUILDS} build ago "
  exit 0
fi

echo -e "\n####### NEED TO CLEAN Volume - starting"


DIR=$(dirname $0)
display_df(){
  echo -e "\nCurrent disk space usage of $VOLUME_PARENT_DIR at $(date) is: "
  df ${VOLUME_PARENT_DIR}

  echo -e"\nCurrent inode usage of $VOLUME_PARENT_DIR at $(date)  is: "
  df -i ${VOLUME_PARENT_DIR}
  echo "---------------------"
}

clean_containers(){
  echo -e "\n############# Cleaning Containers ############# - $(date) "
  if [[ -n "${DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
     docker ps -aq | xargs -n1 echo docker rm -fv
  else
     docker ps -aq | xargs -n1 docker rm -fv
  fi

}

clean_volumes(){
  echo -e "\n############# Cleaning Volumes ############# - $(date) "
  # Listing directories in /var/lib/docker/volumes and delete volume if its folder mtime>VOLUMES_RETAIN_PERIOD
  if [[ -n "${DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
  fi
  for ii in $(find "${DOCKER_VOLUME_DIR}/volumes" -mindepth 1 -maxdepth 1 -type d )
  do
     VOLUME_NAME=$(basename $ii)
     VOLUME_TS=$(date -r ${ii} "+%s")
     VOLUME_TS_AGO=$(( CURRENT_TS - VOLUME_TS ))
     if [[ ${VOLUME_TS_AGO} -ge ${VOLUMES_RETAIN_PERIOD} ]]; then
       echo "Cleaning volume ${VOLUME_NAME} ... "

       if [[ -n "${DRY_RUN}" ]]; then
          echo docker volume rm "${VOLUME_NAME}"
       else
          docker volume rm "${VOLUME_NAME}"
       fi
     fi
  done
}

clean_images(){
  echo -e "\n############# Cleaning Images ############# - $(date) "
  DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events

  # cat events | jq -r 'if .Type == "image" then .id elif .Type == "container" then .from else ""  end' | sort -u

}

clean_containers

clean_volumes

clean_images

echo "---- Cleaning Completed !!! - writing data to LAST_CLEANED_TS_FILE="${LAST_CLEANED_TS_FILE}" and LAST_CLEANED_POD_FILE="${LAST_CLEANED_POD_FILE}
echo ${CURRENT_TS} > "${LAST_CLEANED_TS_FILE}"
echo ${POD_NAME} > "${LAST_CLEANED_POD_FILE}










