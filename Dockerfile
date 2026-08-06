# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:29fe0a7d2a5ab0c236fbde3a7f63801755585ed260b6f2f564e831c92bfa9f34 AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:29fe0a7d2a5ab0c236fbde3a7f63801755585ed260b6f2f564e831c92bfa9f34 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.12.1-alpine3.24@sha256:e77ce1d3ff7a7dfb56dfda8f6485a14f8ab6aecb2d85fa37c6a2fdf41f71ed83 AS node-exporter


FROM docker:29.6.1-dind-rootless@sha256:371962f4344295a1eb185f1c9e62064bf4503a7beb8c6e73be3405500041784b
USER root
RUN chown -R $(id -u rootless) /var /run /lib /home /etc/ssl /etc/apk
# Add community for fuse-overlayfs and edge for jq
RUN echo -en "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/main\nhttps://dl-cdn.alpinelinux.org/alpine/v$(cut -d'.' -f1,2 /etc/alpine-release)/community\n@edge https://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories \
  && apk upgrade \
  && apk add bash jq@edge fuse-overlayfs --no-cache \
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
