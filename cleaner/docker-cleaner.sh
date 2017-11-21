#!/bin/sh
echo "$0 - $(date)" >> /var/log/cleaner.log
DIR=$(dirname $0)
docker run --rm --name rt-cleaner -v /var/run/docker.sock:/var/run/docker.sock:rw \
   -v ${DIR/docker-gc-exclude:/etc/docker-gc-exclude \
   --label io.codefresh.owner=codefresh -e GRACE_PERIOD_SECONDS=86400 \
   codefresh/cf-runtime-cleaner:latest ./docker-gc >> /var/log/cleaner.log 2>&1