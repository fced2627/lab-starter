#!/usr/bin/env bash
# Convert node01/node02 from Vagrant boxes into diskless PXE machines (Module 04).
#
# A machine that boots over the network has no box and no operating system on
# disk — which is the whole point — so Vagrant cannot describe it. From here on
# the compute nodes are created directly against the hypervisor.
#
#   ./nodes-pxe.sh create      define the PXE nodes
#   ./nodes-pxe.sh start|stop|reset NODE
#   ./nodes-pxe.sh console NODE          serial console (your "BMC")
#   ./nodes-pxe.sh destroy
#
# Provider: libvirt if it answers, else QEMU on an ARM host (Apple Silicon: the
# only one there that can network-boot), else VirtualBox. FCED_PROVIDER=libvirt|
# qemu|virtualbox overrides the guess.

set -Eeuo pipefail

GROUP=${FCED_GROUP:-07}
NET="fced-g${GROUP}"
MEM=${FCED_NODE_MEM:-2048}
CPUS=${FCED_NODE_CPUS:-2}
NODES=(node01 node02)
# Fixed MACs: Warewulf identifies a node by its MAC, so these must be stable.
# (A function, not an associative array: macOS ships bash 3.2.)
mac() { case "$1" in node01) echo "52:54:00:fc:ed:01" ;; node02) echo "52:54:00:fc:ed:02" ;; esac; }
HOST_ARCH=$(uname -m)

detect_provider() {
  if [[ -n ${FCED_PROVIDER:-} ]]; then
    echo "$FCED_PROVIDER"
  elif command -v virsh >/dev/null && virsh -c qemu:///system version >/dev/null 2>&1; then
    echo libvirt
  elif [[ $HOST_ARCH == arm64 || $HOST_ARCH == aarch64 ]] && command -v qemu-system-aarch64 >/dev/null; then
    echo qemu
  elif command -v VBoxManage >/dev/null; then
    echo virtualbox
  else
    echo "no supported hypervisor found (need libvirt, QEMU or VirtualBox)" >&2
    exit 1
  fi
}
PROVIDER=$(detect_provider)

lv_create() {
  for n in "${NODES[@]}"; do
    virt-install --name "$n" --memory "$MEM" --vcpus "$CPUS" \
      --network network="$NET",mac="$(mac "$n")",model=virtio \
      --disk size=10,format=qcow2 \
      --boot network,hd --pxe --os-variant rocky9 \
      --graphics none --console pty,target_type=serial --noautoconsole --noreboot
    echo "$n defined, MAC $(mac "$n")"
  done
}
vb_create() {
  # VirtualBox's ARM (Apple Silicon) firmware has no network boot: a PXE-only VM
  # stops at "No bootable option or device was found". See README §4.
  if [[ $HOST_ARCH == arm64 || $HOST_ARCH == aarch64 ]]; then
    echo "VirtualBox on an ARM host cannot PXE-boot a VM: use the QEMU provider (FCED_PROVIDER=qemu, README §4)" >&2
    exit 1
  fi
  for n in "${NODES[@]}"; do
    VBoxManage createvm --name "$n" --ostype RedHat_64 --register
    VBoxManage modifyvm "$n" --memory "$MEM" --cpus "$CPUS" \
      --nic1 intnet --intnet1 "$NET" --nictype1 82540EM \
      --macaddress1 "$(mac "$n" | tr -d :)" \
      --boot1 net --boot2 disk --boot3 none --boot4 none \
      --uart1 0x3F8 4 --uartmode1 server "/tmp/$n.sock"
    VBoxManage createmedium disk --filename "$HOME/VirtualBox VMs/$n/$n.vdi" \
      --size 10240 --format VDI
    VBoxManage storagectl "$n" --name SATA --add sata
    VBoxManage storageattach "$n" --storagectl SATA --port 0 --type hdd \
      --medium "$HOME/VirtualBox VMs/$n/$n.vdi"
    echo "$n defined, MAC $(mac "$n")"
  done
}

# --- QEMU (Apple Silicon) -----------------------------------------------------
# Same VDE switch as the Vagrantfile's QEMU provider. Homebrew's UEFI firmware has
# no network stack, so each node boots iPXE from a tiny read-only FAT drive that
# holds nothing else; iPXE then does DHCP/TFTP/HTTP exactly as a NIC ROM would.
QDIR="$(cd "$(dirname "$0")" && pwd)/.qemu-nodes"
VDE="/tmp/fced-g${GROUP}.vde"
IPXE_URL=https://boot.ipxe.org/arm64-efi/ipxe.efi
sock() { echo "/tmp/fced-g${GROUP}-$1.$2"; }        # short: unix sockets max ~100 chars

qm_vde() {
  local p; p=$(cat "$VDE.pid" 2>/dev/null || true)
  [[ -n $p ]] && kill -0 "$p" 2>/dev/null || vde_switch -s "$VDE" -d -p "$VDE.pid"
}
qm_create() {
  local fw; fw="$(dirname "$(command -v qemu-system-aarch64)")/../share/qemu/edk2-aarch64-code.fd"
  mkdir -p "$QDIR"
  [[ -f $QDIR/ipxe.efi ]] || curl -fsSL -o "$QDIR/ipxe.efi" "$IPXE_URL"
  for n in "${NODES[@]}"; do
    mkdir -p "$QDIR/$n/esp/EFI/BOOT"
    cp "$QDIR/ipxe.efi" "$QDIR/$n/esp/EFI/BOOT/BOOTAA64.EFI"
    cp "$fw" "$QDIR/$n/code.fd"
    rm -f "$QDIR/$n/vars.fd"; dd if=/dev/zero of="$QDIR/$n/vars.fd" bs=1m count=64 2>/dev/null
    echo "$n defined, MAC $(mac "$n")"
  done
}
qm_running() { local p; p=$(cat "$QDIR/$1/qemu.pid" 2>/dev/null || true); [[ -n $p ]] && kill -0 "$p" 2>/dev/null; }
qm_start() {
  [[ -d $QDIR/$1 ]] || { echo "$1 not created: ./nodes-pxe.sh create" >&2; exit 1; }
  qm_running "$1" && { echo "$1 already running"; return; }
  qm_vde
  qemu-system-aarch64 -machine virt,accel=hvf -cpu host -smp "$CPUS" -m "$MEM" \
    -drive if=pflash,format=raw,readonly=on,file="$QDIR/$1/code.fd" \
    -drive if=pflash,format=raw,file="$QDIR/$1/vars.fd" \
    -drive if=none,id=ipxe,format=raw,readonly=on,file="fat:$QDIR/$1/esp" \
    -device virtio-blk-pci,drive=ipxe,bootindex=0 \
    -netdev vde,id=cluster,sock="$VDE" \
    -device virtio-net-pci,netdev=cluster,mac="$(mac "$1")",romfile=,addr=0x9 \
    -display none -serial unix:"$(sock "$1" console)",server=on,wait=off \
    -monitor unix:"$(sock "$1" monitor)",server=on,wait=off \
    -pidfile "$QDIR/$1/qemu.pid" -daemonize
  echo "$1 powered on"
}
qm_monitor() { printf '%s\n' "$2" | nc -U -w 2 "$(sock "$1" monitor)" >/dev/null; }
qm_stop()    { if qm_running "$1"; then qm_monitor "$1" quit; echo "$1 powered off"; else echo "$1 already off"; fi; }
qm_reset()   { qm_monitor "$1" system_reset; echo "$1 reset"; }
qm_console() { echo "(serial console of $1; Ctrl-C to leave)"; nc -U "$(sock "$1" console)"; }
qm_destroy() { for n in "${NODES[@]}"; do [[ -d $QDIR/$n ]] && qm_stop "$n"; rm -rf "${QDIR:?}/$n"; done; }

case "$PROVIDER:${1:-}" in
  libvirt:create)     lv_create ;;
  libvirt:start)      virsh start "$2" ;;
  libvirt:stop)       virsh destroy "$2" ;;
  libvirt:reset)      virsh reset "$2" ;;
  libvirt:console)    virsh console "$2" ;;
  libvirt:destroy)
    for n in "${NODES[@]}"; do virsh destroy "$n" 2>/dev/null || true; virsh undefine "$n" --remove-all-storage; done ;;
  virtualbox:create)  vb_create ;;
  virtualbox:start)   VBoxManage startvm "$2" --type headless ;;
  virtualbox:stop)    VBoxManage controlvm "$2" poweroff ;;
  virtualbox:reset)   VBoxManage controlvm "$2" reset ;;
  virtualbox:console) socat - "UNIX-CONNECT:/tmp/$2.sock" ;;
  virtualbox:destroy)
    for n in "${NODES[@]}"; do
      VBoxManage controlvm "$n" poweroff 2>/dev/null || true
      VBoxManage unregistervm "$n" --delete
    done ;;
  qemu:create)        qm_create ;;
  qemu:start)         qm_start "$2" ;;
  qemu:stop)          qm_stop "$2" ;;
  qemu:reset)         qm_reset "$2" ;;
  qemu:console)       qm_console "$2" ;;
  qemu:destroy)       qm_destroy ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
