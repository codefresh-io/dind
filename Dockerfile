# CI relies on this ARG. Don't remove or rename it
ARG DOCKER_VERSION=29.5.3

# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:e48a91483983467f426cae8656aa16be252c6f2e290125e10db01259352a54ca AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:e48a91483983467f426cae8656aa16be252c6f2e290125e10db01259352a54ca AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.11.1-alpine3.23@sha256:8cd8b3f56f6c319a03c7a2224e99d07e34241ae9ced308df5a6fee41d61ea905 AS node-exporter


FROM docker:${DOCKER_VERSION}-dind-rootless
USER root
RUN chown -R $(id -u rootless) /var /run /lib /home /etc/ssl /etc/apk
# Add community for fuse-overlayfs
RUN echo -en "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/main\nhttps://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/community" > /etc/apk/repositories \
  && apk upgrade \
  && apk add bash jq fuse-overlayfs --no-cache \
  && apk add slirp4netns --no-cache \
  # Needed only for `update-alternatives` below
  && apk add dpkg --no-cache \
  # A security fix till it's fixed in base dind image (CR-31906)
  && apk add git --no-cache --upgrade \
  && rm -rf /var/cache/apk/*
# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN update-alternatives --install $(which iptables) iptables $(which iptables-legacy) 10 \
  && update-alternatives --install $(which ip6tables) ip6tables $(which ip6tables-legacy) 10
ENV DOCKERD_ROOTLESS_ROOTLESSKIT_NET=slirp4netns
COPY --from=node-exporter /usr/bin/node_exporter /bin/
COPY --from=bbolt /go/bin/bbolt /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
WORKDIR /dind
ADD . /dind
RUN chown -R $(id -u rootless) /dind
RUN chown -R $(id -u rootless) /var/run
RUN chown -R $(id -u rootless) /etc/ssl && chmod 777 -R /etc/ssl
USER rootless
RUN rm -i -f /var/run && ln -s /run/user/1000 /var/run
ENTRYPOINT ["./run.sh"]
