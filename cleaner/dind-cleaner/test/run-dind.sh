#!/bin/bash
#
DIR=$(dirname $0)

CONTAINER_NAME=${CONTAINER_NAME:-dind-cleaner-test}
DIND_PORT=${DIND_PORT:-1300}
DIND_IMAGE=codefresh/dind:18.09-v16
#DIND_IMAGE=docker:18.09.2-dind
#DIND_IMAGE_COMMAND=dockerd


CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' ${CONTAINER_NAME} 2>/dev/null)
if [[ $? == 0 ]]; then
   echo "Container ${CONTAINER_NAME} is already ${CONTAINER_STATUS}   
"
	read -r -p "Do you want to recreate it? [y/N] " response
	if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
	then
        echo "Removing container ${CONTAINER_NAME} ..."
        docker rm -fv ${CONTAINER_NAME}
	else
			echo "Exiting..."
			exit 0
	fi
fi

docker run -d --privileged -p ${DIND_PORT}:1300 --name $CONTAINER_NAME \
  -v dind-cleaner-test:/var/lib/docker \
  -v $(realpath $DIR/dind-config-no-tls.json):/etc/docker/daemon.json \
  $DIND_IMAGE $DIND_IMAGE_COMMAND

export DOCKER_HOST=localhost:1300

docker info
echo "export DOCKER_HOST=${DOCKER_HOST}"
bash -ca "export DOCKER_HOST=${DOCKER_HOST}"