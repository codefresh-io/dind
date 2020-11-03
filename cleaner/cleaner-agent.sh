#!/bin/bash
#
# Cleaning agent
# examining usage threshold
# 
echo "$0: - Entering at $(date) "
START_DISK_USAGE_THRESHOLD=0.9
START_INODES_USAGE_THRESHOLD=0.9

DIR=$(dirname ${BASH_SOURCE})

CONFIG_FILE=${DIR}/config
echo "$0: - Loading config File $CONFIG_FILE "
source "${CONFIG_FILE}"

FUNC_FILE=${DIR}/functions.sh
echo "$0: Loading functions File $FUNC_FILE "
source "${FUNC_FILE}"

clean_metrics(){
  [[ -f ${CLEANER_AGENT_ACTIONS_CONTAINERS_FILE} ]] && rm -fv ${CLEANER_AGENT_ACTIONS_CONTAINERS_FILE}
  [[ -f ${CLEANER_AGENT_ACTIONS_VOLUMES_FILE} ]] && rm -fv ${CLEANER_AGENT_ACTIONS_VOLUMES_FILE}
  [[ -f ${CLEANER_AGENT_ACTIONS_IMAGES_FILE} ]] && rm -fv ${CLEANER_AGENT_ACTIONS_IMAGES_FILE}
  [[ -f ${CLEANER_AGENT_ACTIONS_PURGES_FILE} ]] && rm -fv ${CLEANER_AGENT_ACTIONS_PURGES_FILE}
}

sigterm_trap(){
  echo -e "\n    ## $0 - SIGTERM received - $(date) ##"
  export EXIT=1
  rm -vf ${LOCK_FILE}
  clean_metrics
}
trap sigterm_trap SIGTERM SIGINT

need_to_clean() {
  IS_DISK_USAGE_THRESHOLD=$(check_disk_usage_threshold ${START_DISK_USAGE_THRESHOLD})
  IS_INODES_USAGE_THRESHOLD=$(check_inodes_usage_threshold ${START_INODES_USAGE_THRESHOLD})
  if [[ ${IS_DISK_USAGE_THRESHOLD} == 1 || ${IS_INODES_USAGE_THRESHOLD} == 1 ]]; then
      echo 1
  fi
}
SLEEP_INTERVAL=5

echo "$0: initializing metrics"
CLEANER_AGENT_ACTIONS_CONTAINERS=0
CLEANER_AGENT_ACTIONS_VOLUMES=0
CLEANER_AGENT_ACTIONS_IMAGES=0
CLEANER_AGENT_ACTIONS_PURGES=0
clean_metrics

while true
do
  if [[ -n $(need_to_clean) ]]; then
    echo "$0: CLEANER_AGENT: NEEED TO CLEAN - cleaning stopped containers"
    display_df
    lock_file 
    clean_stopped_containers
    (( CLEANER_AGENT_ACTIONS_CONTAINERS ++ ))
    echo "$0: CLEANER_AGENT_ACTIONS_CONTAINERS=$CLEANER_AGENT_ACTIONS_CONTAINERS, updating metric file ${CLEANER_AGENT_ACTIONS_CONTAINERS_FILE}"
    echo $CLEANER_AGENT_ACTIONS_CONTAINERS > ${CLEANER_AGENT_ACTIONS_CONTAINERS_FILE}
    unlock_file
    display_df
  fi
  [[ -n "${EXIT}" ]] && break

  if [[ -n $(need_to_clean) ]]; then
    echo "$0: CLEANER_AGENT: NEEED TO CLEAN - cleaning volumes"
    display_df
    lock_file
    save_events
    clean_volumes
    (( CLEANER_AGENT_ACTIONS_VOLUMES ++ ))
    echo "$0: CLEANER_AGENT_ACTIONS_VOLUMES=$CLEANER_AGENT_ACTIONS_VOLUMES, updating metric file ${CLEANER_AGENT_ACTIONS_VOLUMES_FILE}"
    echo $CLEANER_AGENT_ACTIONS_VOLUMES > ${CLEANER_AGENT_ACTIONS_VOLUMES_FILE}
    unlock_file
    display_df
  fi
  [[ -n "${EXIT}" ]] && break

  if [[ -n $(need_to_clean) ]]; then
    echo "$0: CLEANER_AGENT: NEEED TO CLEAN - cleaning images"
    display_df
    lock_file
    save_events
    clean_images
    (( CLEANER_AGENT_ACTIONS_IMAGES ++ ))
    echo "$0: CLEANER_AGENT_ACTIONS_IMAGES=$CLEANER_AGENT_ACTIONS_IMAGES, updating metric file ${CLEANER_AGENT_ACTIONS_IMAGES_FILE}"
    echo $CLEANER_AGENT_ACTIONS_IMAGES > ${CLEANER_AGENT_ACTIONS_IMAGES_FILE}
    unlock_file
    display_df
  fi
  [[ -n "${EXIT}" ]] && break

  if [[ -n $(need_to_clean) ]]; then
    echo "$0: CLEANER_AGENT: NEEED TO PURGE - purging all images created more than 3h ago"
    display_df
    lock_file
    docker image prune -a --force --filter "until=3h" --filter "label!=io.codefresh.engine=true"
     (( CLEANER_AGENT_ACTIONS_PURGES ++ ))
    echo "$0: CLEANER_AGENT_ACTIONS_PURGES=$CLEANER_AGENT_ACTIONS_PURGES, updating metric file ${CLEANER_AGENT_ACTIONS_PURGES_FILE}"
    echo $CLEANER_AGENT_ACTIONS_PURGES > ${CLEANER_AGENT_ACTIONS_PURGES_FILE}
    echo "docker pull pulling quay.io/codefresh/fs-ops"
    docker pull quay.io/codefresh/fs-ops
    unlock_file
    display_df
  fi
  [[ -n "${EXIT}" ]] && break

  sleep $SLEEP_INTERVAL
done