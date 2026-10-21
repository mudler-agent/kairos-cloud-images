# kairos-hetzner-images

Kairos + k3s disk images, set up for debugging a headless machine. All
variants share the same Kairos master build and baked cloud-config:

| Release tag suffix | OS base | Boot | For |
|---|---|---|---|
| `hadron-…` (no suffix) | Hadron | BIOS | Hetzner Cloud x86 |
| `hadron-…-efi` | Hadron | UEFI | OVHcloud BYOI, other UEFI machines |
| `hadron-…-fw-…-efi` | Hadron + firmware ([`hadron-firmware/Dockerfile`](hadron-firmware/Dockerfile)) | UEFI | bare metal whose NICs need firmware |
| `ubuntu-24.04-…-efi` | Ubuntu 24.04, full `linux-firmware` | UEFI | baseline: if this boots and Hadron does not, the cause is in Hadron |

For a UEFI image the EFI bootloader path is `\EFI\BOOT\BOOTX64.EFI` (shim,
which loads `grubx64.efi`). Turn Secure Boot off for the Hadron images.
Ubuntu's shim is signed with the Microsoft key, but Secure Boot is not tested
on any image.

The images are in [Releases](../../releases). Each release has:

- `*.raw.xz`: use this one for Hetzner (`hcloud-upload-image` takes a raw image).
- `*.qcow2`: the same disk, compressed qcow2, for other KVM clouds and local tests.
- `SHA256SUMS`

## What is inside

| Part       | Version                                                              |
|------------|----------------------------------------------------------------------|
| kairos     | `master` (the release notes give the commit), built from the tree    |
| Hadron     | latest tag (`ghcr.io/kairos-io/hadron:<tag>`)                        |
| AuroraBoot | `main`, built from the tree                                          |
| k3s        | enabled, single node                                                 |

## Import into Hetzner

```sh
hcloud-upload-image upload \
  --image-url https://github.com/mudler-agent/kairos-hetzner-images/releases/download/<tag>/<name>.raw.xz \
  --compression xz --architecture x86 --location fsn1 \
  --description "kairos hadron k3s <tag>"
hcloud server create --name kairos-1 --type cx23 --image <snapshot-id> --location fsn1
```

The disk is 20 GB, so any server type works. On first boot the machine boots
into recovery, resets itself and reboots into the active system. This takes
1 to 2 minutes. The persistent partition then grows to fill the server disk.

Hetzner user-data is optional. When it is given, the built-in `hetzner`
datasource reads it on every boot (`/oem/95_userdata`), on top of the baked
config.

## Install on OVHcloud (UEFI)

In the BYOI form, set the image URL to the `-efi` release's `.qcow2`, the
image type to qcow2, and the EFI bootloader path to `\EFI\BOOT\BOOTX64.EFI`.
SSH keys and userdata from the OVH config drive go through the `config-drive`
datasource. The keys baked into the image work without them.

## Debugging a headless machine

- **SSH:** `ssh kairos@<ip>`. The keys of github.com/mudler are baked in, and
  `github:mudler` is fetched again at boot. Password SSH is off. TCP forwarding
  is on, so `ssh -L 6443:127.0.0.1:6443 kairos@<ip>` reaches the k3s API.
- **Web console** (Hetzner Console, VNC): log in as `kairos` with the console
  password, which is shared out of band and not stored here. After the network
  is up the console shows the Kairos version, the boot mode (active, passive or
  recovery) and the IPs.
- **Kernel cmdline:** it has `rd.immucore.debug rd.kairos.debug` and goes to both
  `ttyS0` and `tty0`. `tty0` is last, so the web console is `/dev/console`.
- **Logs:** journald keeps logs across reboots (`journalctl --list-boots`).
  Kairos logs are in `/var/log/kairos/`. `sudo kairos-agent logs` makes a
  bundle.
- **Recovery:** the recovery system has the same users and keys, so a broken
  active system can be reached over SSH once it boots into recovery. Select
  recovery in the GRUB menu from the web console.

## Hadron firmware

Plain Hadron ships almost no firmware: its initramfs loads Intel, Broadcom and
Mellanox NIC drivers with no firmware files. `hadron-firmware/Dockerfile` copies
the server-relevant pieces of
[kairos-io/hadron-firmware](https://github.com/kairos-io/hadron-firmware) onto
the Hadron base: Intel `ice` (E810), QAT and GPU firmware, Broadcom and
Realtek NIC firmware, AMD microcode, and the loose top-level files. Build it
and use it as `BASE_IMAGE`, so the initramfs that kairos-init builds includes
the firmware too.

## Rebuild

`build.sh` makes every variant. `cloud-config.yaml` and
`cloud-config-ubuntu.yaml` are the baked configs, with the password hash
removed. You need docker, qemu-img and xz.

```sh
# Hetzner (Hadron, BIOS)
./build.sh
# OVHcloud, Hadron + firmware
docker build -t kairos-local/hadron-fw:v0.6.1 hadron-firmware/
BASE_IMAGE=kairos-local/hadron-fw:v0.6.1 DISK=efi ./build.sh
# OVHcloud, Ubuntu baseline
BASE_IMAGE=ubuntu:24.04 CLOUD_CONFIG=$PWD/cloud-config-ubuntu.yaml DISK=efi ./build.sh
```

## Known issues in kairos master (worked around here)

With a top-level `grub_options` in the cloud-config, the first-boot hook
`writeGrubenvToOem` (`agent/internal/agent/hooks/gruboptions.go`) unmounts
`/oem` and does not mount it again. The provider bootstrap that runs right
after it sees no `k3s:` block, so k3s stays down until the next reboot. This
image writes `extra_cmdline` into `/oem/grubenv` with an `initramfs` stage and
does not use `grub_options`. This is kairos-io/kairos#5168 (fix in #5169).

`05-kairos-hardening.conf` from kairos-init lists `mlkem768x25519-sha256`,
which needs OpenSSH 9.9 or later. Ubuntu 24.04 ships OpenSSH 9.6, so sshd
rejects the file and never starts (kairos-io/kairos#5545). An `initramfs` stage
keeps only the algorithms that the installed sshd supports (`ssh -Q`).
