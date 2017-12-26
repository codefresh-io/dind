### Dind Cleaner

Prunes unneeded containers, images, volumes 

We intend to run dind cleaner on every SIGTERM

To determine what to delete we will use information stored in /var/lib/docker/dind-volume 
 - /var/lib/docker/dind-volume/last_cleaned_ts - contains timestamp of last clean (unix timestamp since 1970)
 - /var/lib/docker/dind-volume/last_cleaned_build - contains pod name of last clean
 - /var/lib/docker/dind-volume/events/  - directory with files of docker events list from previous builds. 
  
##### Environent Variables:
  CLEAN_PERIOD_SECONDS
  CLEAN_PERIOD_BUILDS - we will launch clean if last clean was more than CLEAN_PERIOD_SECONDS seconds ago 
           or there was more than  CLEAN_PERIOD_BUILDS nuilds since last build

  IMAGE_RETAIN_PERIOD - we will not delete images if they have events since `current_timestamp - IMAGE_RETAIN_PERIOD` (default 3d)
  VOLUMES_RETAIN_PERIOD - we will not delete volumes if they have events since `current_timestamp - IMAGE_RETAIN_PERIOD` (default 3d)
  
####### defaults:
  CLEAN_PERIOD_SECONDS=${CLEAN_PERIOD_SECONDS:-21600} # 6 hours
  CLEAN_PERIOD_BUILDS=${CLEAN_PERIOD_BUILDS:-10}
  
##### Logic:

- checks last_cleaned_timestamp and exit if: 
  `( current_timestamp - last_cleaned ) < ${CLEAN_PERIOD:-6h}`
  
- Start Cleaning
  * save current docker events by `docker events --until 0s -f ${EVENT_FORMAT} > /var/lib/docker/dind-volume/events/$(date +%s)`
  * concatenate event files newer than greatest from IMAGE_RETAIN_PERIOD and VOLUMES_RETAIN_PERIOD
  * clean all running and exiting containers by `docker rm -vf`
  * clean all images which do not have events since IMAGE_RETAIN_PERIOD
  * clean all volumes which do not have events since VOLUMES_RETAIN_PERIOD
  
- write last_cleaned_timestamp to current filestamp

// TODO
After clean check sum of image sizes

