#!/bin/bash

DIR=$(dirname ${BASH_SOURCE})

CONFIG_FILE=${DIR}/config
source "${CONFIG_FILE}"

lock_file() {
  [[ -f ${LOCK_FILE} ]] && echo "Waiting for another instance of cleaner to stop - ${LOCK_FILE} exists"
  while [[ -f ${LOCK_FILE} ]]
  do
    sleep 1
  done
  echo "Locking - touch ${LOCK_FILE}"
  date +%s > ${LOCK_FILE}
}

unlock_file(){
  echo "Unlocking - rm ${LOCK_FILE}"
  rm -fv ${LOCK_FILE}
}

save_events(){
  FILE_NAME=$(date +%s)
  DOCKER_EVENTS_DIR=${DIND_VOLUME_STAT_DIR}/events
  mkdir -p ${DOCKER_EVENTS_DIR}
  DOCKER_EVENTS_FILE="${DOCKER_EVENTS_DIR}"/"${FILE_NAME}"
  DOCKER_EVENTS_FORMAT='{{ json . }}'
  echo -e "\nSaving current docker events to ${DOCKER_EVENTS_FILE} "
  docker events --until 0s --format "${DOCKER_EVENTS_FORMAT}" > "${DOCKER_EVENTS_FILE}"
}

display_df(){
  echo -e "\nCurrent disk space usage of $DOCKERD_DATA_ROOT at $(date) is: "
  df ${DOCKERD_DATA_ROOT}

  echo -e"\nCurrent inode usage of $DOCKERD_DATA_ROOT at $(date)  is: "
  df -i ${DOCKERD_DATA_ROOT}
  echo "---------------------"
}

check_disk_usage_threshold(){
  local THRESHOLD=${1:-${DISK_USAGE_THRESHOLD}}
  df ${DOCKERD_DATA_ROOT} | awk -v T=${THRESHOLD} 'NR==2 {print ( $3 / $2  > T ) ? "1": "0" }'
}

check_inodes_usage_threshold(){
  local THRESHOLD=${1:-${DISK_USAGE_THRESHOLD}}
   df -i ${DOCKERD_DATA_ROOT} | awk -v T=${THRESHOLD} 'NR==2 {print ( $3 / $2  > T ) ? "1": "0" }'
}

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

clean_stopped_containers(){
  echo -e "\n############# Cleaning Stopped Containers ############# - $(date) "
  DOCKER_RM_PARAMS=$@
  echo "   docker rm params = $DOCKER_RM_PARAMS"
  if [[ -n "${CLEANER_DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
     docker ps -aq --filter "status=exited" | xargs -n1 echo docker rm $DOCKER_RM_PARAMS
  else
     docker ps -aq --filter "status=exited" | xargs -n1 docker rm $DOCKER_RM_PARAMS
  fi
}

clean_containers(){
  echo -e "\n############# Cleaning Containers ############# - $(date) "
  DOCKER_RM_PARAMS=$@
  echo "   docker rm params = $DOCKER_RM_PARAMS"
  if [[ -n "${CLEANER_DRY_RUN}" ]]; then
     echo "Running in DRY_RUN, just display rm commands"
     docker ps -aq | xargs -n1 echo docker rm $DOCKER_RM_PARAMS
  else
     docker ps -aq | xargs -n1 docker rm $DOCKER_RM_PARAMS
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

  CURRENT_TS=$(date +%s)
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

  CURRENT_TS=$(date +%s)
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

  dind-cleaner images --retained-images-file ${RETAINED_IMAGES_FILE} --image-retain-period ${IMAGE_RETAIN_PERIOD}
}



