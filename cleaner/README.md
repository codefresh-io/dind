### Dind Cleaner

Prunes unneeded containers, images, volumes 

We intend to run dind cleaner on every SIGTERM

To determine what to delete we will use information stored in /var/lib/docker/dind-volume 
 - /var/lib/docker/dind-volume/last_cleaned_ts - contains timestamp of last clean (unix timestamp since 1970)
 - /var/lib/docker/dind-volume/last_cleaned_pod - contains pod name of last clean
 - /var/lib/docker/dind-volume/events/  - directory with files of docker events list from previous builds. 
  
##### Environent Variables:
  CLEANER_DRY_RUN - do not actually delete - "echo docker rmi" instead of "docker rmi"
  CLEAN_PERIOD_SECONDS
  CLEAN_PERIOD_BUILDS - we will launch clean if last clean was more than CLEAN_PERIOD_SECONDS seconds ago 
           or there was more than  CLEAN_PERIOD_BUILDS nuilds since last build

  IMAGE_RETAIN_PERIOD - we will not delete images if they have events since `current_timestamp - IMAGE_RETAIN_PERIOD` (default 4h)
  VOLUMES_RETAIN_PERIOD - we will not delete volumes if they have events since `current_timestamp - IMAGE_RETAIN_PERIOD` (default 4h)
  
####### defaults:
  CLEAN_PERIOD_SECONDS: '21600' # launch clean if last clean was more than CLEAN_PERIOD_SECONDS seconds ago
  CLEAN_PERIOD_BUILDS: '5' # launch clean if last clean was more CLEAN_PERIOD_BUILDS builds since last build
  IMAGE_RETAIN_PERIOD: '14400' # do not delete docker images if they have events since current_timestamp - IMAGE_RETAIN_PERIOD
  VOLUMES_RETAIN_PERIOD: '14400' # do not delete docker volumes if they have events since current_timestamp - VOLUMES_RETAIN_PERIOD
  DISK_USAGE_THRESHOLD: '0.8' # launch clean based on current disk usage DISK_USAGE_THRESHOLD
  INODES_USAGE_THRESHOLD: '0.8' # launch clean based on current inodes usage INODES_USAGE_THRESHOLD
  
##### Logic:
- save current docker events by `docker events --until 0s -f ${EVENT_FORMAT} > /var/lib/docker/dind-volume/events/$(date +%s)`
- checks last_cleaned_timestamp and exit if: 
  `( current_timestamp - last_cleaned ) < ${CLEAN_PERIOD_SECONDS} and 
   mount_count since last clean < ${CLEAN_PERIOD_BUILDS}
  `

- Start Cleaning
  * concatenate event files newer than greatest from IMAGE_RETAIN_PERIOD and VOLUMES_RETAIN_PERIOD
  * clean all running and exiting containers by `docker rm -vf`
  * clean all volumes which do not have events since VOLUMES_RETAIN_PERIOD  
  * clean all images which do not have events since IMAGE_RETAIN_PERIOD
  
- write last_cleaned_timestamp to current filestamp

// TODO
After clean check sum of image sizes

