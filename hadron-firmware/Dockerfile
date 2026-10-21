# Hadron base with the firmware plain Hadron leaves out, from
# https://github.com/kairos-io/hadron-firmware (one OCI image per
# linux-firmware folder). Use the result as BASE_IMAGE for kairos-init
# (images/Dockerfile), not on top of a finished Kairos image: kairos-init
# builds the initramfs, and the NIC drivers it loads early need their
# firmware there too.
#
#   docker build -t kairos-local/hadron-fw:v0.6.1 hadron-firmware/
#   BASE_IMAGE=kairos-local/hadron-fw:v0.6.1 ./build.sh
#
# Picked for servers: Intel NIC/QAT/GPU, Broadcom and Realtek NICs, AMD
# microcode, plus the loose files at the top of linux-firmware. No Wi-Fi.
ARG HADRON_TAG=v0.6.1
ARG FIRMWARE_VERSION=20260916
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-intel-ice:${FIRMWARE_VERSION} AS fw-intel-ice
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-intel-generic:${FIRMWARE_VERSION} AS fw-intel-generic
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-intel-qat:${FIRMWARE_VERSION} AS fw-intel-qat
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-i915:${FIRMWARE_VERSION} AS fw-i915
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-xe:${FIRMWARE_VERSION} AS fw-xe
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-bnx2:${FIRMWARE_VERSION} AS fw-bnx2
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-bnx2x:${FIRMWARE_VERSION} AS fw-bnx2x
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-tigon:${FIRMWARE_VERSION} AS fw-tigon
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-rtl_nic:${FIRMWARE_VERSION} AS fw-rtl_nic
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-amd-ucode:${FIRMWARE_VERSION} AS fw-amd-ucode
FROM ghcr.io/kairos-io/hadron-firmware/linux-firmware-uncategorized:${FIRMWARE_VERSION} AS fw-uncategorized

FROM ghcr.io/kairos-io/hadron:${HADRON_TAG}
COPY --from=fw-intel-ice / /
COPY --from=fw-intel-generic / /
COPY --from=fw-intel-qat / /
COPY --from=fw-i915 / /
COPY --from=fw-xe / /
COPY --from=fw-bnx2 / /
COPY --from=fw-bnx2x / /
COPY --from=fw-tigon / /
COPY --from=fw-rtl_nic / /
COPY --from=fw-amd-ucode / /
COPY --from=fw-uncategorized / /
