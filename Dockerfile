# CI relies on this ARG. Don't remove or rename it
ARG DOCKER_VERSION=29.4.1

# dind-cleaner
FROM golang:1.26-alpine3.23 AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


# bbolt
FROM golang:1.26-alpine3.23 AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest

FROM quay.io/containers/skopeo:v1.22.2 AS preloaded-images
COPY images-list.txt /images-list.txt
COPY load-images.sh /load-images.sh
RUN chmod +x /load-images.sh && /load-images.sh /images-list.txt /images

# Main
FROM docker:${DOCKER_VERSION}-dind AS prod
RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.23/main' >> /etc/apk/repositories \
  && apk upgrade && apk add --no-cache \
    bash \
    # Add fuse-overlayfs for compatibility with rootless. Volumes created with rootless might use fuse-overlay formatted volumes. If those volumes are later used by dind that runs with root it'll require fuse-overlay to be able to read the volume
    fuse-overlayfs \
    jq \
    # Needed only for `update-alternatives` below
    dpkg
# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN update-alternatives --install $(which iptables) iptables $(which iptables-legacy) 10 \
  && update-alternatives --install $(which ip6tables) ip6tables $(which ip6tables-legacy) 10
  # DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
COPY --from=docker.io/octopusdeploy/dhi-node-exporter:1.11.1-alpine3.23@sha256:8cd8b3f56f6c319a03c7a2224e99d07e34241ae9ced308df5a6fee41d61ea905 /usr/bin/node_exporter /bin/
COPY --from=bbolt /go/bin/bbolt /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/

# Bake in preloaded image tarballs
COPY --from=preloaded-images /images /preloaded-images

WORKDIR /dind
ADD . /dind

ENTRYPOINT ["./run.sh"]
