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

set -Eeuo pipefail

GROUP=${FCED_GROUP:-07}
NET="fced-g${GROUP}"
MEM=${FCED_NODE_MEM:-2048}
CPUS=${FCED_NODE_CPUS:-2}
NODES=(node01 node02)
# Fixed MACs: Warewulf identifies a node by its MAC, so these must be stable.
declare -A MAC=([node01]="52:54:00:fc:ed:01" [node02]="52:54:00:fc:ed:02")

detect_provider() {
  if command -v virsh >/dev/null && virsh -c qemu:///system version >/dev/null 2>&1; then
    echo libvirt
  elif command -v VBoxManage >/dev/null; then
    echo virtualbox
  else
    echo "no supported hypervisor found (need libvirt or VirtualBox)" >&2
    exit 1
  fi
}
PROVIDER=$(detect_provider)

lv_create() {
  for n in "${NODES[@]}"; do
    virt-install --name "$n" --memory "$MEM" --vcpus "$CPUS" \
      --network network="$NET",mac="${MAC[$n]}",model=virtio \
      --disk size=10,format=qcow2 \
      --boot network,hd --pxe --os-variant rocky9 \
      --graphics none --console pty,target_type=serial --noautoconsole --noreboot
    echo "$n defined, MAC ${MAC[$n]}"
  done
}
vb_create() {
  for n in "${NODES[@]}"; do
    VBoxManage createvm --name "$n" --ostype RedHat_64 --register
    VBoxManage modifyvm "$n" --memory "$MEM" --cpus "$CPUS" \
      --nic1 intnet --intnet1 "$NET" --nictype1 82540EM \
      --macaddress1 "${MAC[$n]//:/}" \
      --boot1 net --boot2 disk --boot3 none --boot4 none \
      --uart1 0x3F8 4 --uartmode1 server "/tmp/$n.sock"
    VBoxManage createmedium disk --filename "$HOME/VirtualBox VMs/$n/$n.vdi" \
      --size 10240 --format VDI
    VBoxManage storagectl "$n" --name SATA --add sata
    VBoxManage storageattach "$n" --storagectl SATA --port 0 --type hdd \
      --medium "$HOME/VirtualBox VMs/$n/$n.vdi"
    echo "$n defined, MAC ${MAC[$n]}"
  done
}

case "${1:-}" in
  create)  [[ $PROVIDER == libvirt ]] && lv_create || vb_create ;;
  start)   [[ $PROVIDER == libvirt ]] && virsh start "$2" || VBoxManage startvm "$2" --type headless ;;
  stop)    [[ $PROVIDER == libvirt ]] && virsh destroy "$2" || VBoxManage controlvm "$2" poweroff ;;
  reset)   [[ $PROVIDER == libvirt ]] && virsh reset "$2" || VBoxManage controlvm "$2" reset ;;
  console) [[ $PROVIDER == libvirt ]] && virsh console "$2" || socat - "UNIX-CONNECT:/tmp/$2.sock" ;;
  destroy)
    for n in "${NODES[@]}"; do
      if [[ $PROVIDER == libvirt ]]; then
        virsh destroy "$n" 2>/dev/null || true; virsh undefine "$n" --remove-all-storage
      else
        VBoxManage controlvm "$n" poweroff 2>/dev/null || true
        VBoxManage unregistervm "$n" --delete
      fi
    done ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
