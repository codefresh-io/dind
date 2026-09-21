# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27-alpine3.24-dev@sha256:47e6ff9623d7f90f2f6e1cd4b0fb129775d8c26e599c4d5da4d66fae1438181d AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27-alpine3.24-dev@sha256:47e6ff9623d7f90f2f6e1cd4b0fb129775d8c26e599c4d5da4d66fae1438181d AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.12.1-alpine3.24@sha256:a8514c8552a97e97b2f8134a13cfd374e080909b6ae56bd8751183908630b9c7 AS node-exporter


FROM docker:29.7.2-dind-rootless@sha256:ec3201de648f98b94882e4dd8a3d30df8b3ca6723a242fab76150f25127e194e
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
  # CVE-2026-17106 (GHSA-hfg8-hc9c-6c3h): the bundled buildx plugin is linked against
  # github.com/moby/go-archive < 0.3.0 and no upstream buildx release ships the fix yet.
  # The plugin is unused here (this image only runs the daemon + cleaner/monitor scripts),
  # so drop it. Revisit once a buildx release with go-archive >= 0.3.0 lands in the base image.
RUN rm -f /usr/local/libexec/docker/cli-plugins/docker-buildx
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
