# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27-alpine3.24-dev@sha256:72cac473a0b802b521e23a2aed591ad166645729533d6d3db4ce96ae22c697ff AS golang


FROM golang AS cleaner
COPY cleaner/dind-cleaner/* /go/src/github.com/codefresh-io/dind-cleaner/
WORKDIR /go/src/github.com/codefresh-io/dind-cleaner/
RUN go mod tidy
COPY cleaner/dind-cleaner/cmd ./cmd/
RUN CGO_ENABLED=0 go build -o /usr/local/bin/dind-cleaner ./cmd \
  && chmod +x /usr/local/bin/dind-cleaner \
  && rm -rf /go/*


FROM golang AS bbolt
RUN go install go.etcd.io/bbolt/cmd/bbolt@latest


FROM golang AS fuse-overlayfs
RUN apk add --no-cache fuse-overlayfs


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.12.1-alpine3.24@sha256:43cad5165557ceb58d3ea4ef6f67398b90893c3e68b811fca2aadec6c2fc2cb5 AS node-exporter


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-docker-dind
FROM octopusdeploy/dhi-docker-dind:29-alpine3.24_dind-test-zhenya@sha256:7e161c1edbabea43a59178550ca37e3b2acdb1be9aa8e66cf9d35aa07567300e AS prod
# The DHI image ships dind's modprobe wrapper at /usr/bin/modprobe, so the wrapper's final
# `exec modprobe` (with /usr/local stripped from PATH) resolves to itself and loops forever.
# This restores the upstream layout: wrapper in /usr/local/bin, real busybox modprobe on the fallback PATH.
RUN rm /usr/local/bin/modprobe \
  && mv /usr/bin/modprobe /usr/local/bin/modprobe \
  && ln -s /bin/busybox /usr/bin/modprobe
# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN ln -sf xtables-legacy-multi /usr/sbin/iptables \
  && ln -sf xtables-legacy-multi /usr/sbin/ip6tables
# Add fuse-overlayfs for compatibility with rootless. Volumes created with rootless might use fuse-overlay formatted volumes.
# If those volumes are later used by dind that runs with root it'll require fuse-overlay to be able to read the volume.
COPY --from=fuse-overlayfs /usr/bin/fuse-overlayfs /usr/bin/
COPY --from=fuse-overlayfs /usr/lib/libfuse3.so.4 /usr/lib/
COPY --from=node-exporter /usr/bin/node_exporter /bin/
COPY --from=bbolt /go/bin/bbolt /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/

# Sanity check
RUN bash --version \
  && jq --version \
  && fuse-overlayfs --version \
  && bbolt version \
  && node_exporter --version \
  && dind-cleaner --help \
  && dockerd --version \
  && docker --version \
  && containerd --version \
  && runc --version \
  && iptables --version \
  && ip6tables --version

WORKDIR /dind
ADD . /dind
ENTRYPOINT ["./run.sh"]
