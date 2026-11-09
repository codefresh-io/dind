# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27-alpine3.24-dev@sha256:95894969dcf353c87cd1b9730e599e1d3c3b7519c8966d28120859609269df4d AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27-alpine3.24-dev@sha256:95894969dcf353c87cd1b9730e599e1d3c3b7519c8966d28120859609269df4d AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.12.1-alpine3.24@sha256:9376bdb044b912b03264ed81117a1a91b5e28f3b45c48ee9ae1988828c45e211 AS node-exporter


FROM docker:29.9.3-dind@sha256:08a98015fce594af7c382883bea080ea206de74402a95da9dc52b6428c8cd121 AS prod
RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.24/main' >> /etc/apk/repositories \
  && apk upgrade && apk add --no-cache \
    bash \
    # Add fuse-overlayfs for compatibility with rootless. Volumes created with rootless might use fuse-overlay formatted volumes. If those volumes are later used by dind that runs with root it'll require fuse-overlay to be able to read the volume
    fuse-overlayfs \
    jq \
    # Needed only for `update-alternatives` below
    dpkg
# CVE-2026-17106 (GHSA-hfg8-hc9c-6c3h): the bundled buildx plugin is linked against
# github.com/moby/go-archive < 0.3.0 and no upstream buildx release ships the fix yet.
# The plugin is unused here (this image only runs the daemon + cleaner/monitor scripts),
# so drop it. Revisit once a buildx release with go-archive >= 0.3.0 lands in the base image.
RUN rm -f /usr/local/libexec/docker/cli-plugins/docker-buildx
# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN update-alternatives --install $(which iptables) iptables $(which iptables-legacy) 10 \
  && update-alternatives --install $(which ip6tables) ip6tables $(which ip6tables-legacy) 10
COPY --from=node-exporter /usr/bin/node_exporter /bin/
COPY --from=bbolt /go/bin/bbolt /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
WORKDIR /dind
ADD . /dind
ENTRYPOINT ["./run.sh"]
