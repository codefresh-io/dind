FROM quay.io/prometheus/node-exporter:v0.15.1 AS node-exporter
# install node-exporter

FROM codefresh/dind-cleaner:v1.1 AS dind-cleaner

FROM docker:18.09.5-dind
RUN apk add bash jq --no-cache
COPY --from=node-exporter /bin/node_exporter /bin/
COPY --from=dind-cleaner /usr/local/bin/dind-cleaner /bin/

WORKDIR /dind
ADD . /dind

CMD ["./run.sh"]
