FROM quay.io/prometheus/node-exporter:v0.15.1 AS node-exporter
# install node-exporter

FROM docker:17.06.0-ce-dind
RUN apk add bash --no-cache
COPY --from=node-exporter /bin/node_exporter /bin/

WORKDIR /dind
ADD . /dind

CMD ["./run.sh"]
