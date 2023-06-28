ARG DOCKER_VERSION=20.10.18

# dind-cleaner
FROM golang:1.16-alpine3.15 AS cleaner

COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/

RUN go mod tidy

COPY cleaner/dind-cleaner/cmd ./cmd/

RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd && \
  chmod +x /usr/local/bin/dind-cleaner && \
  rm -rf /go/*

# bolter
FROM golang:1.19-alpine3.16 AS bolter
RUN apk add git
RUN go install github.com/hasit/bolter@v0.0.0-20210331045447-e1283cecdb7b

# node-exporter
FROM quay.io/prometheus/node-exporter:v1.5.0 AS node-exporter

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
COPY --from=bolter /go/bin/bolter /bin/

WORKDIR /dind
ADD . /dind

RUN chown -R $(id -u rootless) /dind
RUN chown -R $(id -u rootless) /var/run

RUN chown -R $(id -u rootless) /etc/ssl && chmod 777 -R /etc/ssl
USER rootless
RUN rm -i -f /var/run && ln -s /run/user/1000 /var/run
ENTRYPOINT ["./run.sh"]
