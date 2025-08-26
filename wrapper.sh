#!/bin/bash

apk add --no-cache util-linux \
  && unshare --cgroup /bin/sh -c 'umount /sys/fs/cgroup && mount -t cgroup2 cgroup /sys/fs/cgroup && /dind/run.sh "$0" "$@"'
  "$0" "$@"
