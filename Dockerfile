ARG DOCKER_VERSION=28.5.2


# dind-cleaner
FROM golang:1.25-alpine3.23 AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd && \
  chmod +x /usr/local/bin/dind-cleaner && \
  rm -rf /go/*


# bbolt
FROM golang:1.25-alpine3.23 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


# node-exporter
FROM quay.io/prometheus/node-exporter:v1.10.2 AS node-exporter


# Install dependencies
FROM docker:${DOCKER_VERSION}-dind AS dependencies
RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.22/main' >> /etc/apk/repositories \
  && apk upgrade && apk add --no-cache \
    bash \
    # Add fuse-overlayfs for compatibility with rootless. Volumes created with rootless might use fuse-overlay formatted volumes. If those volumes are later used by dind that runs with root it'll require fuse-overlay to be able to read the volume
    fuse-overlayfs \
    jq \
    # Needed only for `update-alternatives` below
    dpkg


# Main
FROM docker:${DOCKER_VERSION}-dind AS prod
COPY --from=dependencies /bin/bash /bin/bash
COPY --from=dependencies /usr/bin/fuse-overlayfs /usr/bin/fuse-overlayfs
COPY --from=dependencies /usr/bin/jq /usr/bin/jq
COPY --from=dependencies /usr/bin/update-alternatives /usr/bin/update-alternatives
# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN update-alternatives --install $(which iptables) iptables $(which iptables-legacy) 10 \
  && update-alternatives --install $(which ip6tables) ip6tables $(which ip6tables-legacy) 10
COPY --from=node-exporter /bin/node_exporter /bin/
COPY --from=bbolt /go/bin/bbolt /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/

WORKDIR /dind
ADD . /dind

ENTRYPOINT ["./run.sh"]
