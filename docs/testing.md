# Testing on aurora

Only my delta over stock gets tested; ublue already tests the base. Four levels,
and only the last one touches the real OS:

| level | where | time |
|---|---|---|
| 1. build + `bootc container lint` | CI, every PR and push to `main` | automatic |
| 2. smoke test inside the image (`tests/smoke.sh`) | CI after every build; by hand below | ~10 min, mostly the pull |
| 3. VM: boot, Plasma, sysstate UI | aurora, below | ~40 min |
| 4. `rpm-ostree rebase` on the machine | README, "Move a host onto its image" | ~15 min + reboots |

Everything below runs in a terminal on aurora, logged in at the desk: several
steps need `sudo` with a password.

## 0. Access to the images (once per boot)

The packages on ghcr are private, so podman needs a login.

```
gh auth refresh -h github.com -s read:packages   # once: adds the scope, opens a browser
gh auth token | podman login ghcr.io -u 4bdulla --password-stdin
gh auth token | sudo podman login ghcr.io -u 4bdulla --password-stdin
```

Both logins live in `/run` and are gone after a reboot. Don't copy this token
into `/etc/ostree/auth.json` for level 4: it reaches every repo of the
account. For that, create a classic token with only `read:packages`, or make
the packages public.

Get the repo:

```
git clone https://github.com/4bdulla/custom-image ~/Projects/custom-image
cd ~/Projects/custom-image
```

## 1. Signature

```
cosign verify --key cosign.pub ghcr.io/4bdulla/aurora-host:latest > /dev/null
```

Expected: `The signatures were verified against the specified public key`.

## 2. Smoke test

```
podman pull ghcr.io/4bdulla/aurora-host:latest
podman run --rm -e HOST=aurora -v "$PWD":/repo:ro --security-opt label=disable \
  --entrypoint bash ghcr.io/4bdulla/aurora-host:latest /repo/tests/smoke.sh
```

Expected: every line `PASS`, last line `all checks passed`. The same script
runs in CI after each build; for bazzite, use `HOST=bazzite` and
`bazzite-host`.

## 3. VM

### Build the disk (~20 min)

```
mkdir -p ~/vm/aurora-host && cd ~/vm/aurora-host
cat > config.toml <<'EOF'
[[customizations.user]]
name = "tester"
password = "tester"
groups = ["wheel"]

[[customizations.filesystem]]
mountpoint = "/"
minsize = "40 GiB"
EOF

sudo podman pull ghcr.io/4bdulla/aurora-host:latest
sudo podman run --rm -it --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v ./config.toml:/config.toml:ro \
  -v ./output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --rootfs btrfs --use-librepo=True \
  ghcr.io/4bdulla/aurora-host:latest

sudo cp output/qcow2/disk.qcow2 /var/lib/libvirt/images/aurora-host-test.qcow2
```

The copy is there because libvirt under SELinux can't read a disk in `~`.

### Start it

```
sudo virt-install --name aurora-host-test --memory 6144 --vcpus 4 --cpu host-passthrough \
  --disk path=/var/lib/libvirt/images/aurora-host-test.qcow2,format=qcow2,bus=virtio \
  --import --osinfo detect=on,require=off \
  --graphics spice --video virtio --noautoconsole
virt-manager --connect qemu:///system --show-domain-console aurora-host-test
```

### Check inside the VM

Log in as `tester` / `tester`. Pass = each line below holds.

1. **Plasma session opens** after login.
2. **The VM runs my image.** In Konsole: `rpm-ostree status` shows
   `aurora-host` as the booted deployment.
3. **The sysstate timer is enabled with no setup.**
   `systemctl --user list-timers sysstate-collect.timer` shows a next run
   within 30 minutes.
4. **Collection works.** `sysstate collect; sysstate status` prints the table
   of rpm-ostree / flatpak / brew / distrobox.
5. **The UI opens.** App launcher → *System State*: a browser opens
   `http://127.0.0.1:8765` with the same sources. If the first-boot flatpak
   install hasn't finished and there is no browser yet, run `sysstate serve`
   and check with `curl -s 127.0.0.1:8765 | head`.
6. **Rolling back works.** `sudo bootc switch ghcr.io/ublue-os/aurora-dx:stable`,
   reboot: stock aurora-dx boots. `sudo rpm-ostree rollback`, reboot: back
   on `aurora-host`, and checks 2–4 still hold.

Out of scope for the VM: NVIDIA, fans, real screens. Those are level 4.

### Clean up

```
sudo virsh destroy aurora-host-test
sudo virsh undefine aurora-host-test --nvram
sudo rm /var/lib/libvirt/images/aurora-host-test.qcow2
sudo rm -rf ~/vm/aurora-host/output
sudo podman rmi ghcr.io/4bdulla/aurora-host:latest
```
