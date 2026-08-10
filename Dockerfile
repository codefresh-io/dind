# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:753793e50e16daafaf70566409c752ed05f177fb34ad5b488918bbccae462413 AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:753793e50e16daafaf70566409c752ed05f177fb34ad5b488918bbccae462413 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.12.1-alpine3.24@sha256:e77ce1d3ff7a7dfb56dfda8f6485a14f8ab6aecb2d85fa37c6a2fdf41f71ed83 AS node-exporter


FROM docker:29.7.1-dind@sha256:e8faad5a8dc5279dff929afc5449f2791736912fff9f99351d742db2fad01b4c AS prod
RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.24/main' >> /etc/apk/repositories \
  && echo '@edge http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories \
  && apk upgrade && apk add --no-cache \
    bash \
    # Add fuse-overlayfs for compatibility with rootless. Volumes created with rootless might use fuse-overlay formatted volumes. If those volumes are later used by dind that runs with root it'll require fuse-overlay to be able to read the volume
    fuse-overlayfs \
    jq@edge \
    # Needed only for `update-alternatives` below
    dpkg
# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN update-alternatives --install $(which iptables) iptables $(which iptables-legacy) 10 \
  && update-alternatives --install $(which ip6tables) ip6tables $(which ip6tables-legacy) 10
COPY --from=node-exporter /usr/bin/node_exporter /bin/
COPY --from=bbolt /go/bin/bbolt /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
WORKDIR /dind
ADD . /dind
ENTRYPOINT ["./run.sh"]
