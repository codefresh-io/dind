FROM quay.io/prometheus/node-exporter:v0.15.1 AS node-exporter
# install node-exporter

FROM docker:17.06-dind
RUN apk add bash jq python3 --no-cache
COPY --from=node-exporter /bin/node_exporter /bin/

WORKDIR /dind
ADD . /dind

CMD ["./run.sh"]
