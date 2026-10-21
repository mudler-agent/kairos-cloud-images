#!/usr/bin/env bash
# Rebuild the Hetzner (BIOS) Kairos + Hadron + k3s disk image.
#   kairos:     master, built from the tree (kairos-init + images/Dockerfile)
#   hadron:     ghcr.io/kairos-io/hadron:$HADRON_TAG
#   auroraboot: main, built from the tree
# Usage: KAIROS_DIR=~/src/kairos AURORABOOT_DIR=~/src/AuroraBoot ./build.sh
#   BASE_IMAGE=kairos-local/hadron-fw:v0.6.1  Hadron + firmware (hadron-firmware/Dockerfile)
#   BASE_IMAGE=ubuntu:24.04 CLOUD_CONFIG=$PWD/cloud-config-ubuntu.yaml
#   DISK=efi                                  UEFI disk (OVHcloud) instead of BIOS (Hetzner)
set -euo pipefail
: "${KAIROS_DIR:?path to a kairos checkout}" "${AURORABOOT_DIR:?path to an AuroraBoot checkout}"
: "${HADRON_TAG:=v0.6.1}" "${OUT:=$PWD/out}" "${CLOUD_CONFIG:=$PWD/cloud-config.yaml}"
: "${BASE_IMAGE:=ghcr.io/kairos-io/hadron:$HADRON_TAG}" "${DISK:=bios}"
here=$PWD
cd "$KAIROS_DIR"
sha=$(git rev-parse --short HEAD)
make binaries ARCH=amd64
make image-kairos-init ARCH=amd64 IMAGE_REGISTRY=kairos-local IMAGE_TAG=hetzner
docker build -f images/Dockerfile . \
  --build-arg BASE_IMAGE=$BASE_IMAGE \
  --build-arg KAIROS_INIT_IMAGE=kairos-local/kairos-init:hetzner \
  --build-arg MODEL=generic --build-arg TRUSTED_BOOT=false \
  --build-arg KUBERNETES_DISTRO=k3s --build-arg VERSION=v4.3.0-master.$sha \
  -t kairos-local/kairos-hadron-k3s:hetzner
cd "$AURORABOOT_DIR"
docker build --build-arg VERSION=main-$(git rev-parse --short HEAD) -t kairos-local/auroraboot:main .
mkdir -p "$OUT"
# disk.bios: Hetzner Cloud x86 boots legacy BIOS. disk.efi: UEFI (OVHcloud BYOI). disk.size is in MB and must
# not exceed the smallest server disk you deploy to (40 GB on the cheapest).
docker run --rm --privileged -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$OUT":/output -v "$CLOUD_CONFIG":/cc.yaml kairos-local/auroraboot:main \
  --set container_image=docker://kairos-local/kairos-hadron-k3s:hetzner \
  --set disk.$DISK=true --set disk.size=20000 \
  --set disable_http_server=true --set disable_netboot=true \
  --set state_dir=/output --cloud-config /cc.yaml
docker run --rm -v "$OUT":/output --entrypoint chown kairos-local/auroraboot:main -R "$(id -u):$(id -g)" /output
cd "$OUT"
raw=$(ls -t ./*.raw | head -1)
name=kairos-$(echo "${BASE_IMAGE##*/}" | tr ':' '-')-k3s-master-$sha-$DISK
qemu-img convert -c -O qcow2 "$raw" "$name.qcow2"
xz -T0 -6 -k -c "$raw" > "$name.raw.xz"
sha256sum "$name.qcow2" "$name.raw.xz" > SHA256SUMS
cd "$here"
