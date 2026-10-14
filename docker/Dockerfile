# Pinned so that builds stay byte-for-byte reproducible: the base image by digest
# and the packages (mksquashfs above all) through a fixed snapshot.debian.org date.
FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
ARG UID=1000
RUN echo 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20261001T000000Z bookworm main' > /etc/apt/sources.list && \
    rm -f /etc/apt/sources.list.d/* && \
    apt-get -o Acquire::Check-Valid-Until=false update && apt-get install -y --no-install-recommends \
      bash coreutils findutils grep sed gawk file git ca-certificates sudo \
      squashfs-tools u-boot-tools p7zip-full xz-utils zstd jq perl python3 \
      bsdextrautils xxd tar gzip && rm -rf /var/lib/apt/lists/* && \
    useradd -m -u "$UID" builder && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder && \
    git config --system --add safe.directory '*'
USER builder
