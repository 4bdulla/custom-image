# custom-image

BlueBuild images for the two hosts. Each recipe is that host's profile,
system part: base image, packages, services, defaults.

| recipe | base | image |
|---|---|---|
| `recipes/bazzite.yml` | `bazzite-nvidia-open:stable` | `ghcr.io/4bdulla/bazzite-host` |
| `recipes/aurora.yml` | `aurora-dx:stable` | `ghcr.io/4bdulla/aurora-host` |

`recipes/common.yml` holds what both share: sysstate (staged by CI from the
sysstate repo, `SYSSTATE_REF` in `build.yml`), image signing, and
`bootc container lint`.

## CI secrets

- `SIGNING_SECRET` - the cosign private key. `cosign.pub` is its pair.
- `SYSSTATE_DEPLOY_KEY` - private half of a read-only deploy key on
  `4bdulla/sysstate`.

## Check a recipe locally

```
podman run --rm -v "$PWD":/bluebuild:Z -w /bluebuild ghcr.io/blue-build/cli:v0.9.37 bluebuild validate recipes/aurora.yml
```

## Move a host onto its image

aurora first, bazzite last. Needs sudo, so interactive only.

```
sudo ostree admin pin 0      # keep the stock deployment in the boot menu
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/4bdulla/aurora-host:latest
systemctl reboot
# the first boot installs the signing policy; from now on only signed updates
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/4bdulla/aurora-host:latest
systemctl reboot
```

Then drop the per-user sysstate install, which would shadow the image's units
(commands in the sysstate README, "In an OS image").

On bazzite the image already carries the three layered packages, so drop the
layer requests in the first rebase:

```
sudo rpm-ostree rebase --uninstall=coolercontrol --uninstall=ghostty --uninstall=liquidctl \
  ostree-unverified-registry:ghcr.io/4bdulla/bazzite-host:latest
```

Back to stock: `sudo rpm-ostree rollback` and reboot, or pick the old entry in
GRUB.
