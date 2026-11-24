# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-golang
FROM octopusdeploy/dhi-golang:1.27.4-alpine3.24-dev@sha256:f5765dcea1354da7d6b6e12eb84949fed6336dc9c022edc49af932be879f71c0 AS golang


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


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-node-exporter
FROM octopusdeploy/dhi-node-exporter:1.13.1-alpine3.24@sha256:7f7dc3854a9fd6b908908f1c36b12ba03836662a9bc1259427583390c09f17de AS node-exporter


# The DHI customization catalogue only offers packages from the DHI and Alpine `main` repositories,
# so the rootless tooling that lives in Alpine `community` is installed here and copied into the runtime image.
FROM golang AS rootless-extras
RUN apk add --no-cache shadow-subids slirp4netns fuse-overlayfs


# DHI source: https://hub.docker.com/repository/docker/octopusdeploy/dhi-docker-dind
# The runtime image has no package manager: bash, jq, rootlesskit, iproute2-minimal, fuse3, libbsd, glib
# and libseccomp are added through DHI customization, together with the `rootless` user (uid 1000).
# iproute2-minimal is there because rootlesskit needs `ip tuntap`, which busybox `ip` does not implement.
FROM octopusdeploy/dhi-docker-dind:29.10.0-alpine_cf-classic-dind-rootless@sha256:2f1288f8483aa74a59df9248b9859c3ab74c38b3d828cb6cbd082850771d6079 AS prod
USER root
# The DHI image ships dind's modprobe wrapper at /usr/bin/modprobe, so the wrapper's final
# `exec modprobe` (with /usr/local stripped from PATH) resolves to itself and loops forever.
# Restore the upstream layout: wrapper in /usr/local/bin, real busybox modprobe on the fallback PATH.
RUN rm /usr/local/bin/modprobe \
  && mv /usr/bin/modprobe /usr/local/bin/modprobe \
  && ln -s /bin/busybox /usr/bin/modprobe
# Backward compatibility with kernels that do not support `iptables-nft`. Check #CR-23033 for details.
RUN ln -sf xtables-legacy-multi /usr/sbin/iptables \
  && ln -sf xtables-legacy-multi /usr/sbin/ip6tables
# The `rootless` user itself comes from the DHI customization; the rest follows upstream `docker:dind-rootless`.
RUN echo 'rootless:100000:65536' >> /etc/subuid \
  && echo 'rootless:100000:65536' >> /etc/subgid \
  && mkdir -p /run/user/1000 /home/rootless/.local/share/docker \
  && chmod 1777 /run/user \
  && chown -R rootless /var /run /lib /home /etc/ssl
# DHI images declare no volumes. Without one the data root sits on the container's overlay filesystem, where overlay2 cannot be mounted.
VOLUME /home/rootless/.local/share/docker
# setuid instead of the file capabilities the Alpine package sets, because those do not survive every builder's COPY.
COPY --from=rootless-extras --chmod=4755 /usr/bin/newuidmap /usr/bin/newgidmap /usr/bin/
COPY --from=rootless-extras /usr/lib/libslirp.so.0 /usr/lib/
COPY --from=rootless-extras /usr/bin/slirp4netns /usr/bin/fuse-overlayfs /usr/bin/
ENV DOCKERD_ROOTLESS_ROOTLESSKIT_NET=slirp4netns
COPY --from=node-exporter /usr/bin/node_exporter /bin/
COPY --from=bbolt /go/bin/bbolt /bin/
COPY --from=cleaner /usr/local/bin/dind-cleaner /bin/
WORKDIR /dind
ADD . /dind
RUN chown -R rootless /dind /var/run \
  && chown -R rootless /etc/ssl && chmod 777 -R /etc/ssl
USER rootless
RUN rm -i -f /var/run && ln -s /run/user/1000 /var/run
# Fail the build if a binary is missing or cannot load its libraries: part of them depends on the
# DHI customization staying in place, the rest is copied from other stages or expected from the base image.
RUN bash --version \
  && jq --version \
  && rootlesskit --version \
  && ip -V \
  && newuidmap 2>&1 | grep -q usage \
  && newgidmap 2>&1 | grep -q usage \
  && slirp4netns --version \
  && fuse-overlayfs --version \
  && fusermount3 --version \
  && bbolt version \
  && node_exporter --version \
  && dind-cleaner --help \
  && dockerd --version \
  && docker --version \
  && containerd --version \
  && runc --version \
  && iptables --version \
  && ip6tables --version
ENTRYPOINT ["./run.sh"]
