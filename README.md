# kairos-cloud-images

Kairos + Hadron + k3s disk images for machines that boot in **legacy BIOS**
mode, set up for debugging a headless machine. Tested on:

- Hetzner Cloud x86 servers
- OVHcloud bare metal (Intel DH67BL / Xeon E3-1245 v2, "Bring Your Own Image").
  The OVH install form asks for an EFI bootloader path, but this server boots
  legacy BIOS, so EFI images never start on it.

The images are in [Releases](../../releases). Each release has:

- `*.qcow2`: for OVHcloud BYOI and other KVM-style imports.
- `*.raw.xz`: for Hetzner (`hcloud-upload-image` takes a raw image).
- `SHA256SUMS`

Earlier releases with `-efi` in the tag are UEFI experiments. They are not
built any more.

## What is inside

| Part       | Version                                                   |
|------------|-----------------------------------------------------------|
| kairos     | `master` (the release notes give the commit)              |
| Hadron     | `v0.6.1` by default (`ghcr.io/kairos-io/hadron`)          |
| AuroraBoot | `main`                                                    |
| k3s        | server or worker, flannel on WireGuard (`wireguard-native`) |
| Disk       | 20 GB, GPT with a BIOS boot partition                     |

On first boot the machine boots into recovery, creates the state and
persistent partitions, resets itself and reboots into the active system. This
takes 2 to 4 minutes. The persistent partition then grows to fill the disk.

## Build

Run the **Build image** workflow (Actions → Build image → Run workflow). It
builds on a GitHub runner and publishes a release. Inputs:

- `role`: `server` or `worker`. See [Add workers](#add-workers).
- `firmware`: add the server firmware from `hadron-firmware/Dockerfile`. See
  [Hadron firmware](#hadron-firmware).
- `hadron_tag`, `kairos_ref`, `auroraboot_ref`: the versions to build.

The console password hash comes from the `CONSOLE_PASSWD_HASH` repository
secret (`openssl passwd -6`).

To build locally you need docker, go, qemu-img and xz:

```sh
KAIROS_DIR=~/src/kairos AURORABOOT_DIR=~/src/AuroraBoot ./build.sh
FIRMWARE=true KAIROS_DIR=... AURORABOOT_DIR=... ./build.sh
```

Put your own password hash in `cloud-config.yaml` first.

## Install on OVHcloud (BYOI)

1. In the install form, choose "Bring Your Own Image".
2. Set the image URL to the `.qcow2` from a release, and the image type to
   `qcow2`.
3. The form also asks for an EFI bootloader path. Enter
   `\EFI\BOOT\BOOTX64.EFI`. A BIOS server does not use it.
4. Start the install. The server answers ping during OVH's own install step.
   SSH opens only after our image has booted.

To check whether a server boots BIOS or UEFI, install one of OVH's own
templates and run `ls /sys/firmware/efi`. If the directory does not exist,
the server boots legacy BIOS.

## Add workers

The server image runs k3s with `--flannel-backend=wireguard-native`. Flannel
puts the pod traffic between nodes in WireGuard tunnels (UDP port 51820), so
that traffic is encrypted also when it goes over the public network. The
agent-to-server traffic is TLS already.

The worker image has no server URL and no join token. A release asset is
public, so a token in the image gives anyone a way to join the cluster. Give
the URL and the token to each worker at install time:

1. On the server, read the token: `sudo cat /var/lib/rancher/k3s/server/node-token`.
2. Install the `k3s-worker` qcow2 with BYOI. Turn on the config drive and set
   its user data to:

   ```yaml
   #cloud-config
   k3s-agent:
     env:
       K3S_URL: https://<server-ip>:6443
       K3S_TOKEN: <token>
   ```

   Kairos reads the `config-2` config drive on the first boot and writes the
   user data to `/oem/95_userdata`.
3. If the config drive is not available, SSH into the worker, put the same
   YAML in `/oem/95_join.yaml`, and reboot. The provider sets up k3s once and
   then writes `/usr/local/.kairos/deployed`. On a worker whose agent has no
   server URL yet, a `boot.before` stage removes that marker, so the reboot
   runs the setup again.
4. On the server, run `sudo k3s kubectl get nodes`.

To turn on WireGuard on a server that runs `vxlan`, put
`flannel-backend: wireguard-native` in `/etc/rancher/k3s/config.yaml` and
restart k3s.

## Install on Hetzner Cloud

```sh
hcloud-upload-image upload \
  --image-url https://github.com/mudler-agent/kairos-cloud-images/releases/download/<tag>/<name>.raw.xz \
  --compression xz --architecture x86 --location fsn1 \
  --description "kairos hadron k3s <tag>"
hcloud server create --name kairos-1 --type cx23 --image <snapshot-id> --location fsn1
```

## Debugging a headless machine

- **SSH:** `ssh kairos@<ip>`. The keys of github.com/mudler are baked in, and
  `github:mudler` is fetched again at boot. Password SSH is off. TCP forwarding
  is on, so `ssh -L 6443:127.0.0.1:6443 kairos@<ip>` reaches the k3s API.
- **Console:** log in as `kairos` with the console password. It is shared out
  of band and not stored here. After the network is up, the console shows the
  Kairos version, the boot mode (active, passive or recovery) and the IPs.
- **Kernel cmdline:** it has `rd.immucore.debug rd.kairos.debug` and goes to
  both `ttyS0` and `tty0`.
- **Logs:** journald keeps logs across reboots (`journalctl --list-boots`).
  Kairos logs are in `/var/log/kairos/`. `sudo kairos-agent logs` makes a
  bundle.
- **Recovery:** the recovery system has the same users and keys. During the
  first boot you can already SSH into it.

## Hadron firmware

Plain Hadron ships almost no firmware. Its initramfs loads the Intel,
Broadcom and Mellanox NIC drivers with no firmware files. Many NICs keep their
firmware on the card and work anyway (the OVH Intel 82579V on `e1000e` does).
Other NICs need firmware from the OS, for example the Intel E810 (`ice`) and
some Broadcom and Realtek chips.

`hadron-firmware/Dockerfile` copies the server-relevant parts of
[kairos-io/hadron-firmware](https://github.com/kairos-io/hadron-firmware) onto
the Hadron base: Intel `ice`, QAT and GPU firmware, Broadcom and Realtek NIC
firmware, AMD microcode, and the loose top-level files. `build.sh` uses it as
the base image for kairos-init, so the initramfs includes the firmware too.

## Known issues in kairos master (worked around here)

With a top-level `grub_options` in the cloud-config, the first-boot hook
`writeGrubenvToOem` (`agent/internal/agent/hooks/gruboptions.go`) unmounts
`/oem` and does not mount it again. The provider bootstrap that runs right
after it sees no `k3s:` block, so k3s stays down until the next reboot. This
image writes `extra_cmdline` into `/oem/grubenv` with an `initramfs` stage and
does not use `grub_options`. This is kairos-io/kairos#5168 (fix in #5169).
