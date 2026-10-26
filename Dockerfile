# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27-alpine3.24-dev@sha256:2ceb813d69b9c82501323484e0c0ae612efde281f5dffce2a3d83a79a9c87304 AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27-alpine3.24-dev@sha256:2ceb813d69b9c82501323484e0c0ae612efde281f5dffce2a3d83a79a9c87304 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.12.1-alpine3.24@sha256:bfb8df90caafe3f7429ab528a957d63979c6e435dc01c74530e9542613da019e AS node-exporter


FROM docker:29.9.2-dind@sha256:9e79b879b177fbd72c34376a3dd3d91747da5db49e1f560f76aea59561471977 AS prod
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
