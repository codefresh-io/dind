#!/bin/bash
#
# Cleaning dind
# see README.md for details
#
echo "Entering $0 at $(date) "

CLEAN_PERIOD_SECONDS=${CLEAN_PERIOD_SECONDS:-21600}
CLEAN_PERIOD_BUILDS=${CLEAN_PERIOD_BUILDS:-10}

IMAGE_RETAIN_PERIOD=${IMAGE_RETAIN_PERIOD:-259200}
VOLUMES_RETAIN_PERIOD=${VOLUMES_RETAIN_PERIOD:-259200}

DISK_USAGE_THRESHOLD=${DISK_USAGE_THRESHOLD:-0.8}
INODES_USAGE_THRESHOLD=${INODES_USAGE_THRESHOLD:-0.8}

#CLEANER_DRY_RUN=1
echo "
CLEAN_PERIOD_SECONDS=${CLEAN_PERIOD_SECONDS}
CLEAN_PERIOD_BUILDS=${CLEAN_PERIOD_BUILDS}
IMAGE_RETAIN_PERIOD=${IMAGE_RETAIN_PERIOD}
VOLUMES_RETAIN_PERIOD=${VOLUMES_RETAIN_PERIOD}
CLEANER_DRY_RUN=${CLEANER_DRY_RUN}
DISK_USAGE_THRESHOLD=${DISK_USAGE_THRESHOLD}
INODES_USAGE_THRESHOLD=${INODES_USAGE_THRESHOLD}
"

#### Defining DIND_VOLUME_STAT dir and stat files
DOCKERD_DATA_ROOT=${DOCKERD_DATA_ROOT:-/var/lib/docker}
DIND_VOLUME_STAT_DIR=${DIND_VOLUME_STAT_DIR:-${DOCKERD_DATA_ROOT}/dind-volume}
mkdir -p ${DIND_VOLUME_STAT_DIR}

LAST_CLEANED_TS_FILE=${DIND_VOLUME_STAT_DIR}/last_cleaned_ts
LAST_CLEANED_POD_FILE=${DIND_VOLUME_STAT_DIR}/last_cleaned_pod
DIND_VOLUME_USED_BY_PODS_FILE=${DIND_VOLUME_STAT_DIR}/pods

POD_NAME=${POD_NAME:-$(hostname)}
CURRENT_TS=$(date +%s)

#### Current Docker events
#DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events
#DOCKER_EVENTS_FILE="${DOCKER_EVENTS_DIR}"/${CURRENT_TS}
#DOCKER_EVENTS_FORMAT='{{ json . }}'
#echo -e "\nSaving current docker events to ${DOCKER_EVENTS_FILE} "
#docker events --until 0s --format "${DOCKER_EVENTS_FORMAT}" > "${DOCKER_EVENTS_FILE}"

DIR=$(dirname $0)
display_df(){
  echo -e "\nCurrent disk space usage of $DOCKERD_DATA_ROOT at $(date) is: "
  df ${DOCKERD_DATA_ROOT}

  echo -e"\nCurrent inode usage of $DOCKERD_DATA_ROOT at $(date)  is: "
  df -i ${DOCKERD_DATA_ROOT}
  echo "---------------------"
}
display_df

#### Checking if we need to clean by dind stat
NEED_TO_CLEEN=""

echo -e "\nChecking if  need to clean by last cleaned date - CLEAN_PERIOD_SECONDS=${CLEAN_PERIOD_SECONDS}"
if [[ ! -f "${LAST_CLEANED_TS_FILE}" ]]; then
  echo "First launch of dind cleaner - ${LAST_CLEANED_TS_FILE} file does not exist. Creating"
  echo ${CURRENT_TS} > "${LAST_CLEANED_TS_FILE}"
else

  LAST_CLEANED_TS=$(cat ${LAST_CLEANED_TS_FILE})
  LAST_CLEANED_SECONDS_AGO=$(( CURRENT_TS - LAST_CLEANED_TS ))
  echo "LAST_CLEANED_TS = ${LAST_CLEANED_TS} CURRENT_TS = ${CURRENT_TS}, LAST_CLEANED_SECONDS_AGO = ${LAST_CLEANED_SECONDS_AGO} vs CLEAN_PERIOD_SECONDS = ${CLEAN_PERIOD_SECONDS} "
  if [[ ${LAST_CLEANED_SECONDS_AGO} -ge ${CLEAN_PERIOD_SECONDS} ]]; then
    echo "NEED TO CLEAN: Volume was last cleaned ${LAST_CLEANED_SECONDS_AGO} seconds ago"
    NEED_TO_CLEEN=1
  fi
fi

echo -e "\nChecking if  need to clean by last cleaned pod - CLEAN_PERIOD_BUILDS=${CLEAN_PERIOD_BUILDS}"
if [[ ! -f "${LAST_CLEANED_POD_FILE}" ]]; then
  echo "First launch of dind cleaner - ${LAST_CLEANED_POD_FILE} file does not exist. Creating"
  echo ${POD_NAME} > "${LAST_CLEANED_POD_FILE}"
fi

LAST_CLEANED_POD_NAME=$(cat ${LAST_CLEANED_POD_FILE})
if [[ -z "${LAST_CLEANED_POD_NAME}" ]]; then
   LAST_CLEANED_POD_NAME=${POD_NAME}
fi
LAST_CLEANED_POD_LINE_GREP=$(grep -n ${LAST_CLEANED_POD_NAME} "${DIND_VOLUME_USED_BY_PODS_FILE}" | tail -n1)
THIS_POD_LINE_GREP=$(grep -n ${POD_NAME} "${DIND_VOLUME_USED_BY_PODS_FILE}" | tail -n1)

if [[ -n "${LAST_CLEANED_POD_LINE_GREP}" && -n "${THIS_POD_LINE_GREP}" ]]; then
  LAST_CLEANED_POD_LINE=$(echo "${LAST_CLEANED_POD_LINE_GREP}" | cut -d":" -f1)
  THIS_POD_LINE=$(echo "${THIS_POD_LINE_GREP}" | cut -d":" -f1)
  LAST_CLEANED_BUILDS_AGO=$(( THIS_POD_LINE - LAST_CLEANED_POD_LINE ))
  echo "LAST_CLEANED_BUILDS_AGO = ${LAST_CLEANED_BUILDS_AGO} vs CLEAN_PERIOD_BUILDS = ${CLEAN_PERIOD_BUILDS}"
  if [[ ${LAST_CLEANED_BUILDS_AGO} -ge ${CLEAN_PERIOD_BUILDS} ]]; then
      echo "NEED TO CLEAN: Volume was last cleaned ${LAST_CLEANED_BUILDS_AGO} builds ago"
      NEED_TO_CLEEN=1
  fi
else
  echo "WARNING: cannot find LAST_CLEANED_POD_NAME=${LAST_CLEANED_POD_NAME} or THIS_POD=${POD_NAME} in DIND_VOLUME_USED_BY_PODS_FILE=${DIND_VOLUME_USED_BY_PODS_FILE} "
fi

check_disk_usage_threshold(){
   df ${DOCKERD_DATA_ROOT} | awk -v T=${DISK_USAGE_THRESHOLD} 'NR==2 {print ( $3 / $2  > T ) ? "1": "0" }'
}

check_inodes_usage_threshold(){
   df -i ${DOCKERD_DATA_ROOT} | awk -v T=${INODES_USAGE_THRESHOLD} 'NR==2 {print ( $3 / $2  > T ) ? "1": "0" }'
}

echo -e "\nChecking if  need to clean by current disk usage - DISK_USAGE_THRESHOLD = ${DISK_USAGE_THRESHOLD}"
IS_DISK_USAGE_THRESHOLD=$(check_disk_usage_threshold)
if [[ ${IS_DISK_USAGE_THRESHOLD} == 1 ]]; then
   echo "NEED TO CLEAN: Volume ${DOCKERD_DATA_ROOT} disk usage thershold ${DISK_USAGE_THRESHOLD} reached"
   NEED_TO_CLEEN=1
fi

echo -e "\nChecking if  need to clean by current inodes usage - INODE_USAGE_THRESHOLD = ${INODES_USAGE_THRESHOLD}"
IS_INODES_USAGE_THRESHOLD=$(check_inodes_usage_threshold)
if [[ ${IS_INODES_USAGE_THRESHOLD} == 1 ]]; then
   echo "NEED TO CLEAN: Volume ${DOCKERD_DATA_ROOT} inodes usage thershold ${INODES_USAGE_THRESHOLD} reached"
   NEED_TO_CLEEN=1
fi

clean_temporary_objects(){
  echo -e "\n############# Cleaning Images label=io.codefresh.operationName=Exporting volume data ############# - $(date) "
  for ii in $(docker images -q -f 'label=io.codefresh.operationName=Exporting volume data')
  do
    if [[ -n "${CLEANER_DRY_RUN}" ]]; then
      echo "Running in DRY_RUN, just display rm commands"
      echo docker rmi $ii
    else
      docker rmi $ii
    fi
  done
}

clean_containers(){
  echo -e "\n############# Cleaning Containers ############# - $(date) "
  if [[ -n "${CLEANER_DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
     docker ps -aq | xargs -n1 echo docker rm -f
  else
     docker ps -aq | xargs -n1 docker rm -f
  fi

}

clean_networks(){
  echo -e "\n############# Cleaning Networks ############# - $(date) "
  if [[ -n "${CLEANER_DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
     echo docker network prune -f
  else
     docker network prune -f
  fi
}

clean_volumes(){
  echo -e "\n############# Cleaning Volumes ############# - $(date) "
  # Listing directories in /var/lib/docker/volumes and delete volume if its folder mtime>VOLUMES_RETAIN_PERIOD
  if [[ -n "${CLEANER_DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
  fi

  DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events
  RETAINED_VOLUMES_FILE=/tmp/retained_volumes.$$
  rm -f ${RETAINED_VOLUMES_FILE}

  echo "Finding recently used volumes by saved events within VOLUMES_RETAIN_PERIOD= ${VOLUMES_RETAIN_PERIOD}s"
  for ii in $(find "${DOCKER_EVENTS_DIR}/" -mindepth 1 -maxdepth 1 -type f )
  do
    EVENTS_FILE_TS=$(basename $ii)
    EVENTS_FILE_TS_AGO=$(( CURRENT_TS - EVENTS_FILE_TS ))
    if [[ ${EVENTS_FILE_TS_AGO} -le ${VOLUMES_RETAIN_PERIOD} ]]; then
      echo "    Finding volumes from event file $ii and writing names to ${RETAINED_VOLUMES_FILE}"
      cat ${ii} | jq -r 'if .Type == "volume" then .Actor["ID"] else "" end' \
         | sort -u >> ${RETAINED_VOLUMES_FILE}
    fi
  done

  for ii in $(find "${DOCKERD_DATA_ROOT}/volumes" -mindepth 1 -maxdepth 1 -type d )
  do
    VOLUME_NAME=$(basename $ii)

    echo -e "\n ---- Checking volume ${VOLUME_NAME} for deletion"
    if grep -q ${VOLUME_NAME} ${RETAINED_VOLUMES_FILE}; then
        echo "    Volume ${VOLUME_NAME} should be retained - appears in RETAINED_VOLUMES_FILE"
        continue
    fi

    echo "    Cleaning volume ${VOLUME_NAME} ... "
    if [[ -n "${CLEANER_DRY_RUN}" ]]; then
      echo docker volume rm "${VOLUME_NAME}"
    else
      docker volume rm "${VOLUME_NAME}"
    fi
  done
}

clean_images(){
  echo -e "\n############# Cleaning Images ############# - $(date) "
  # We are looking images that should be retained in events
  # operating with image ID without "sha256:"
  #    docker image inspect --format '{{ .ID }}' "${image_name}" | sed  -E 's/^sha256:(.*)/\1/'
  # Finding descendand (child) docker images using docker_descendants.py script

  if [[ -n "${CLEANER_DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
  fi
  DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events
  RETAINED_IMAGES_FILE=/tmp/retained_images.$$
  rm -f ${RETAINED_IMAGES_FILE} ${RETAINED_IMAGES_FILE}.names

  echo "Finding recently used images by saved events within IMAGE_RETAIN_PERIOD=${IMAGE_RETAIN_PERIOD}s"
  for ii in $(find "${DOCKER_EVENTS_DIR}/" -mindepth 1 -maxdepth 1 -type f )
  do
     EVENTS_FILE_TS=$(basename $ii)
     EVENTS_FILE_TS_AGO=$(( CURRENT_TS - EVENTS_FILE_TS ))
     if [[ ${EVENTS_FILE_TS_AGO} -le ${IMAGE_RETAIN_PERIOD} ]]; then
       echo "    Finding images from event file $ii and writing names to ${RETAINED_IMAGES_FILE}.names"
       cat ${ii} | jq -r 'if .Type == "image" then .id elif .Type == "container" then .Actor["Attributes"]["imageID"] + "\n" + .Actor["Attributes"]["image"] else ""  end' \
       | sort -u >> ${RETAINED_IMAGES_FILE}.names
     fi
  done

  if [[ -f ${RETAINED_IMAGES_FILE}.names ]]; then
     echo "    For all lines in ${RETAINED_IMAGES_FILE}.names we find its ID and write to ${RETAINED_IMAGES_FILE}"
     cat ${RETAINED_IMAGES_FILE}.names | while read image_name
     do
       if [[ -n "${image_name}" ]]; then
          docker image inspect --format '{{ .ID }}' "${image_name}" >> "${RETAINED_IMAGES_FILE}"
       fi
     done
  fi

  dind-cleaner images --retained-images-file ${RETAINED_IMAGES_FILE}
}

clean_containers
display_df
clean_temporary_objects
display_df
clean_networks

if [[ -z "${NEED_TO_CLEEN}" ]]; then
  echo "NO need to clean, EXITING: running on new volume or it was cleaned less than ${CLEAN_PERIOD_SECONDS} ago it was cleaned less than ${CLEAN_PERIOD_BUILDS} build ago "
  exit 0
fi

echo -e "\n####### NEED TO CLEAN volumes and/or images - starting"
clean_volumes

clean_images

echo "---- Cleaning Completed !!! - writing data to LAST_CLEANED_TS_FILE="${LAST_CLEANED_TS_FILE}" and LAST_CLEANED_POD_FILE="${LAST_CLEANED_POD_FILE}
if [[ -z "${CLEANER_DRY_RUN}" ]]; then
    echo ${CURRENT_TS} > "${LAST_CLEANED_TS_FILE}"
    echo ${POD_NAME} > "${LAST_CLEANED_POD_FILE}"
fi

display_df

# Checking if need to prune
NEED_TO_PRUNE=""
echo -e "\nChecking if need to prune if after cleaning current disk usage - DISK_USAGE_THRESHOLD = ${DISK_USAGE_THRESHOLD}"
IS_DISK_USAGE_THRESHOLD=$(check_disk_usage_threshold)
if [[ ${IS_DISK_USAGE_THRESHOLD} == 1 ]]; then
   echo "NEED TO PRUNE: Volume ${DOCKERD_DATA_ROOT} after cleaning disk usage thershold ${DISK_USAGE_THRESHOLD} reached"
   NEED_TO_PRUNE=1
fi

IS_INODES_USAGE_THRESHOLD=$(check_inodes_usage_threshold)
if [[ ${IS_INODES_USAGE_THRESHOLD} == 1 ]]; then
   echo "NEED TO PRUNE: Volume ${DOCKERD_DATA_ROOT} after cleaner inodes usage thershold ${INODES_USAGE_THRESHOLD} reached"
   NEED_TO_PRUNE=1
fi

if [[ -z "${NEED_TO_PRUNE}" ]]; then
  echo "NO need to prune "
  exit 0
else
  echo "executing docker system prune -a --volumes --force"
  if [[ -n "${CLEANER_DRY_RUN}" ]]; then
    echo "Dry run mode - do not actually prune"
  else
    LAST_PRUNED_TS_FILE=${DIND_VOLUME_STAT_DIR}/last_pruned_ts
    LAST_PRUNED_POD_FILE=${DIND_VOLUME_STAT_DIR}/last_pruned_pod
    docker system prune -a --volumes --force
    
    display_df
    echo "---- Pruning Completed !!! - writing data to LAST_PRUNED_TS_FILE="${LAST_PRUNED_TS_FILE}" and LAST_PRUNED_POD_FILE="${LAST_PRUNED_POD_FILE}
    echo $(date +%s) > "${LAST_PRUNED_TS_FILE}"
    echo ${POD_NAME} > "${LAST_PRUNED_POD_FILE}"
  fi
fi







