#!/usr/bin/env bash
# Build the Kairos + Hadron + k3s BIOS disk image.
#   kairos:     master (or KAIROS_DIR's checkout), built from the tree
#   hadron:     ghcr.io/kairos-io/hadron:$HADRON_TAG
#   auroraboot: main (or AURORABOOT_DIR's checkout), built from the tree
# Usage: KAIROS_DIR=~/src/kairos AURORABOOT_DIR=~/src/AuroraBoot ./build.sh
#   FIRMWARE=true   add the server firmware from hadron-firmware/Dockerfile
set -euo pipefail
: "${KAIROS_DIR:?path to a kairos checkout}" "${AURORABOOT_DIR:?path to an AuroraBoot checkout}"
: "${HADRON_TAG:=v0.6.1}" "${FIRMWARE:=false}" "${OUT:=$PWD/out}" "${CLOUD_CONFIG:=$PWD/cloud-config.yaml}"
here=$PWD

base=ghcr.io/kairos-io/hadron:$HADRON_TAG
flavor=hadron-$HADRON_TAG
if [ "$FIRMWARE" = true ]; then
  docker build --build-arg HADRON_TAG="$HADRON_TAG" -t "kairos-local/hadron-fw:$HADRON_TAG" hadron-firmware/
  base=kairos-local/hadron-fw:$HADRON_TAG
  flavor=hadron-fw-$HADRON_TAG
fi

cd "$KAIROS_DIR"
sha=$(git rev-parse --short HEAD)
make binaries ARCH=amd64
make image-kairos-init ARCH=amd64 IMAGE_REGISTRY=kairos-local IMAGE_TAG=hetzner
docker build -f images/Dockerfile . \
  --build-arg BASE_IMAGE="$base" \
  --build-arg KAIROS_INIT_IMAGE=kairos-local/kairos-init:hetzner \
  --build-arg MODEL=generic --build-arg TRUSTED_BOOT=false \
  --build-arg KUBERNETES_DISTRO=k3s --build-arg VERSION="v4.3.0-master.$sha" \
  -t kairos-local/kairos-hadron-k3s:hetzner

cd "$AURORABOOT_DIR"
docker build --build-arg VERSION="main-$(git rev-parse --short HEAD)" -t kairos-local/auroraboot:main .
mkdir -p "$OUT"
# disk.bios: legacy BIOS boot (Hetzner Cloud x86, the OVH DH67BL boxes). On
# first boot the disk boots recovery, creates COS_STATE and COS_PERSISTENT,
# resets and reboots into active. disk.size is in MB and must not exceed the
# smallest disk you deploy to.
docker run --rm --privileged -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$OUT":/output -v "$CLOUD_CONFIG":/cc.yaml kairos-local/auroraboot:main \
  --set container_image=docker://kairos-local/kairos-hadron-k3s:hetzner \
  --set disk.bios=true --set disk.size=20000 \
  --set disable_http_server=true --set disable_netboot=true \
  --set state_dir=/output --cloud-config /cc.yaml
docker run --rm -v "$OUT":/output --entrypoint chown kairos-local/auroraboot:main -R "$(id -u):$(id -g)" /output

cd "$OUT"
raw=$(ls -t ./*.raw | head -1)
name=kairos-$flavor-k3s-master-$sha-bios
qemu-img convert -c -O qcow2 "$raw" "$name.qcow2"
xz -T0 -6 -k -c "$raw" > "$name.raw.xz"
sha256sum "$name.qcow2" "$name.raw.xz" > SHA256SUMS
cd "$here"
