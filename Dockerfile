ARG DOCKER_VERSION=20.10.18

# dind-cleaner
FROM golang:1.16-alpine3.15 AS cleaner

COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/

RUN go mod tidy

COPY cleaner/dind-cleaner/cmd ./cmd/

RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd && \
    chmod +x /usr/local/bin/dind-cleaner && \
    rm -rf /go/*

# bolter
FROM golang:1.19-alpine3.16 AS bolter
RUN go install github.com/hasit/bolter@v0.0.0-20210331045447-e1283cecdb7b

# node-exporter
FROM quay.io/prometheus/node-exporter:v1.4.0 AS node-exporter

# Main
FROM docker:${DOCKER_VERSION}-dind

RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.11/main' >> /etc/apk/repositories \
  && apk upgrade \
  # Add fuse-overlayfs for comaptibility with rootless. Volumes created with rootless might use fuse-overlay formatted volumes. If those volumes are later used by dind that runs with root it'll require fuse-overlay to be able to read the volume
  && apk add bash fuse-overlayfs jq --no-cache \
  && rm -rf /var/cache/apk/*

COPY --from=node-exporter /bin/node_exporter /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
COPY --from=bolter /go/bin/bolter /bin/

WORKDIR /dind
ADD . /dind

ENTRYPOINT ["./run.sh"]
