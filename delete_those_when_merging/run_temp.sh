#!/bin/bash



export DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS="-p 0.0.0.0:1300:1300/tcp" # Expose rooltelsskit port
#dockerd-entrypoint.sh dockerd <&- &
DOCKERD_PID=$(cat /run/user/1000/docker.pid)

while true; do
     if [ -d "/proc/$DOCKERD_PID" ]; then
      echo "Running"
   else
      echo "Docker daemon no longer running"
      exit 1
   fi
sleep 1;
done

