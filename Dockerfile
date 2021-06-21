ARG DOCKER_VERSION=18.09.5

FROM quay.io/prometheus/node-exporter:v0.15.1 AS node-exporter
# install node-exporter

FROM codefresh/dind-cleaner:v1.0 AS dind-cleaner

FROM golang:alpine3.7 as build-plugin

WORKDIR /go/src/github.com/authz-plugin
ADD authz-plugin/ .
RUN go build -o authz-plugin .

FROM docker:18.06-dind
RUN apk add bash jq --no-cache
COPY --from=node-exporter /bin/node_exporter /bin/
COPY --from=dind-cleaner /usr/local/bin/dind-cleaner /bin/
COPY --from=build-plugin /go/src/github.com/authz-plugin/authz-plugin /bin/
COPY --from=build-plugin /go/src/github.com/authz-plugin/pluginConfig.json /dind/

WORKDIR /dind
ADD /dind /dind

CMD ["./run.sh"]
