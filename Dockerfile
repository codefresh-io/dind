FROM docker:17.06.0-ce-dind

ARG BUILD_DOCKER_HOST

COPY . /

CMD ["run.sh"]
