#!/usr/bin/env bash
# Test level 2: check my delta inside a built image, without booting it.
# Runs inside the image; the repo is mounted at /repo for cosign.pub.
#
#   podman run --rm -e HOST=aurora -v "$PWD":/repo:ro --security-opt label=disable \
#     --entrypoint bash ghcr.io/4bdulla/aurora-host:latest /repo/tests/smoke.sh
#
# HOST is aurora or bazzite. Exits non-zero if any check fails.
set -uo pipefail

host="${HOST:?set HOST=aurora or HOST=bazzite}"
image="${host}-host"
failed=0

check() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $what"
  else
    echo "FAIL  $what"
    failed=1
  fi
}

# sysstate, staged from its repo and enabled for every user.
check "sysstate binary runs"                 /usr/bin/sysstate help
check "collect unit runs /usr/bin/sysstate"  grep -q '^ExecStart=/usr/bin/sysstate collect' /usr/lib/systemd/user/sysstate-collect.service
check "collect timer installed"              test -f /usr/lib/systemd/user/sysstate-collect.timer
check "collect timer enabled globally"       test -L /etc/systemd/user/timers.target.wants/sysstate-collect.timer
check "UI desktop entry installed"           test -f /usr/share/applications/sysstate-ui.desktop

# Signing: the host must refuse an update not signed by our key.
check "our public key is the repo's cosign.pub" cmp -s /repo/cosign.pub "/etc/pki/containers/${image}.pub"
check "policy requires our signature"           grep -q "ghcr.io/4bdulla/${image}" /etc/containers/policy.json

if [ "$host" = bazzite ]; then
  # These replace the rpm-ostree layers on the host.
  check "coolercontrol, ghostty, liquidctl installed" rpm -q coolercontrol ghostty liquidctl
  # Terra was enabled for one transaction only; the image keeps it off, as stock does.
  check "terra repo stays disabled"                   grep -q '^enabled=0' /etc/yum.repos.d/terra.repo
fi

[ "$failed" = 0 ] && echo "all checks passed" || echo "some checks failed"
exit "$failed"
