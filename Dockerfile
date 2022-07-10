ARG DOCKER_VERSION=20.10.13

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
FROM golang:1.16-alpine3.15 AS bolter
RUN apk add git
RUN go get -u github.com/hasit/bolter

# node-exporter
FROM quay.io/prometheus/node-exporter:v1.0.0 AS node-exporter

# Main
FROM docker:${DOCKER_VERSION}-dind

RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.11/main' >> /etc/apk/repositories \
  && apk upgrade \
  && apk add bash jq --no-cache \
  && rm -rf /var/cache/apk/*

COPY --from=node-exporter /bin/node_exporter /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
COPY --from=bolter /go/bin/bolter /bin/

WORKDIR /dind
ADD . /dind

RUN adduser -D -h /home/cfu -s /bin/bash cfu \
    && chgrp -R $(id -g cfu) /var /etc /root \
    && chmod -R g+rwX /var /etc /root

USER cfu

ENTRYPOINT ["./run.sh"]
