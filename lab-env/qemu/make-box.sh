#!/bin/bash
# Build the local Vagrant box used by the QEMU provider on Apple Silicon.
#
# There is no working Rocky 9 aarch64 box for vagrant-qemu on Vagrant Cloud (the
# official rockylinux/9 libvirt/arm64 download returns 404). This converts Bento's
# VirtualBox arm64 box, which Module 01 already uses, into the libvirt box format
# that vagrant-qemu reads. Nothing inside the image is changed: the Vagrantfile
# attaches the disk and the NAT NIC so that the image finds what it expects.
#
#   ./qemu/make-box.sh          # once; takes about a minute
#
# Result: a box called fced/rockylinux-9-qemu (vagrant box list).

set -euo pipefail

SRC_BOX=bento/rockylinux-9
NAME=fced/rockylinux-9-qemu
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fced-box.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

command -v qemu-img >/dev/null || { echo "qemu-img not found: brew install qemu" >&2; exit 1; }

vagrant box list | grep -q "^$SRC_BOX .*virtualbox.*arm64" ||
  vagrant box add "$SRC_BOX" --provider virtualbox --architecture arm64

VMDK=$(ls -t "${VAGRANT_HOME:-$HOME/.vagrant.d}"/boxes/bento-VAGRANTSLASH-rockylinux-9/*/arm64/virtualbox/*.vmdk | head -1)
echo "converting $VMDK"
qemu-img convert -O qcow2 "$VMDK" "$WORK/box.img"
SIZE=$(qemu-img info --output=json "$WORK/box.img" | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"] // 2**30)')

cat > "$WORK/metadata.json" <<EOF
{"provider": "libvirt", "format": "qcow2", "virtual_size": $SIZE, "architecture": "arm64"}
EOF
cat > "$WORK/Vagrantfile" <<'EOF'
Vagrant.configure("2") do |config|
end
EOF

tar -C "$WORK" -czf "$WORK/fced.box" metadata.json Vagrantfile box.img
vagrant box add --force --name "$NAME" "$WORK/fced.box"
vagrant box list | grep "^$NAME"
