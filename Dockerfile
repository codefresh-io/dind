ARG DOCKER_VERSION=25.0.4

# dind-cleaner
FROM golang:1.22-alpine3.19 AS cleaner

COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/

RUN go mod tidy

COPY cleaner/dind-cleaner/cmd ./cmd/

RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd && \
  chmod +x /usr/local/bin/dind-cleaner && \
  rm -rf /go/*

# bbolt
FROM golang:1.22-alpine3.19 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest

# node-exporter
FROM quay.io/prometheus/node-exporter:v1.7.0 AS node-exporter

# Main
FROM docker:${DOCKER_VERSION}-dind-rootless

USER root

RUN chown -R $(id -u rootless) /var /run /lib /home /etc/ssl /etc/apk

# Add community for fuse-overlayfs
RUN echo -en "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/main\nhttps://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/community" > /etc/apk/repositories \
  && apk upgrade \
  && apk add bash jq fuse-overlayfs --no-cache \
  && apk add slirp4netns --no-cache \
  && rm /usr/local/bin/vpnkit \
  && rm -rf /var/cache/apk/*

ENV DOCKERD_ROOTLESS_ROOTLESSKIT_NET=slirp4netns

COPY --from=node-exporter /bin/node_exporter /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
COPY --from=bbolt /go/bin/bbolt /bin/

WORKDIR /dind
ADD . /dind

RUN chown -R $(id -u rootless) /dind
RUN chown -R $(id -u rootless) /var/run

RUN chown -R $(id -u rootless) /etc/ssl && chmod 777 -R /etc/ssl
USER rootless
RUN rm -i -f /var/run && ln -s /run/user/1000 /var/run
ENTRYPOINT ["./run.sh"]
