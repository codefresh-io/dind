#!/bin/bash
#
# Cleaning dind
# see README.md for details
#
echo "Entering $0 at $(date) "

DIR=$(dirname ${BASH_SOURCE})

CONFIG_FILE=${DIR}/config
echo "Loading config File $CONFIG_FILE "
source "${CONFIG_FILE}"

FUNC_FILE=${DIR}/functions.sh
echo "Loading functions File $FUNC_FILE "
source "${FUNC_FILE}"

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

LAST_CLEANED_POD_FILE=${DIND_VOLUME_STAT_DIR}/last_cleaned_pod
DIND_VOLUME_USED_BY_PODS_FILE=${DIND_VOLUME_STAT_DIR}/pods

LAST_PRUNED_POD_FILE=${DIND_VOLUME_STAT_DIR}/last_pruned_pod

POD_NAME=${POD_NAME:-$(hostname)}
CURRENT_TS=$(date +%s)

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

clean_containers -f
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
    docker system prune -a --volumes --force
    
    display_df
    echo "---- Pruning Completed !!! - writing data to LAST_PRUNED_TS_FILE="${LAST_PRUNED_TS_FILE}" and LAST_PRUNED_POD_FILE="${LAST_PRUNED_POD_FILE}
    echo $(date +%s) > "${LAST_PRUNED_TS_FILE}"
    echo ${POD_NAME} > "${LAST_PRUNED_POD_FILE}"
  fi
fi
