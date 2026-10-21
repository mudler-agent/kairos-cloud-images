# kairos-hetzner-images

Kairos + Hadron + k3s disk images for Hetzner Cloud (x86, legacy BIOS boot),
set up for debugging a headless machine.

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

## Rebuild

`build.sh` and `cloud-config.yaml` (with the password hash removed) make the
same image. You need docker, qemu-img and xz.

## Known issue in kairos master (worked around here)

With a top-level `grub_options` in the cloud-config, the first-boot hook
`writeGrubenvToOem` (`agent/internal/agent/hooks/gruboptions.go`) unmounts
`/oem` and does not mount it again. The provider bootstrap that runs right
after it sees no `k3s:` block, so k3s stays down until the next reboot. This
image writes `extra_cmdline` into `/oem/grubenv` with an `initramfs` stage and
does not use `grub_options`.
