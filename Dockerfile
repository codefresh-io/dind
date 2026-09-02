# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:b8c24c4df0722866243706e44f4c622e1487f1272d7f9ea89944f6832f9cc801 AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.26-alpine3.24-dev@sha256:b8c24c4df0722866243706e44f4c622e1487f1272d7f9ea89944f6832f9cc801 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.12.1-alpine3.24@sha256:a8514c8552a97e97b2f8134a13cfd374e080909b6ae56bd8751183908630b9c7 AS node-exporter


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
