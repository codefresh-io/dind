ARG DOCKER_VERSION=28.5.1

# dind-cleaner
FROM golang:1.25-alpine3.22 AS cleaner

COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/

RUN go mod tidy

COPY cleaner/dind-cleaner/cmd ./cmd/

RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd && \
  chmod +x /usr/local/bin/dind-cleaner && \
  rm -rf /go/*

# bbolt
FROM golang:1.25-alpine3.22 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest

# node-exporter
FROM quay.io/prometheus/node-exporter:v1.9.1 AS node-exporter

# Main
FROM docker:${DOCKER_VERSION}-dind

RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.22/main' >> /etc/apk/repositories \
  && apk upgrade \
  # Add fuse-overlayfs for comaptibility with rootless. Volumes created with rootless might use fuse-overlay formatted volumes. If those volumes are later used by dind that runs with root it'll require fuse-overlay to be able to read the volume
  && apk add bash fuse-overlayfs jq --no-cache \
  # Needed only for `update-alternatives` below
  && apk add dpkg --no-cache \
  && rm -rf /var/cache/apk/*

# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN update-alternatives --install $(which iptables) iptables $(which iptables-legacy) 10 \
  && update-alternatives --install $(which ip6tables) ip6tables $(which ip6tables-legacy) 10

COPY --from=node-exporter /bin/node_exporter /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
COPY --from=bbolt /go/bin/bbolt /bin/

WORKDIR /dind
ADD . /dind

ENTRYPOINT ["./run.sh"]
