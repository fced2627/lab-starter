# The lab environment

Every lab and the project run on **four virtual machines on your own laptop**. There is no shared
teaching cluster: your cluster is yours, it lives on your disk, and if you break it you rebuild it.

That is not a compromise forced by circumstance — it is the same property the course asks of you all
semester. If the cluster cannot be rebuilt from files in git, you do not have a cluster.

---

## 1. What you need

| | Minimum | Comfortable |
|---|---|---|
| RAM | 16 GB (8 GB with the reduced profile — see §5) | 16 GB or more |
| CPU | 4 cores with virtualisation enabled in firmware | 8 cores |
| Disk | 40 GB free | 80 GB free |
| Network | Internet access from the VMs, for package and image downloads | — |

The full profile allocates **8 GB of RAM and 7 vCPU** across four machines. vCPU oversubscription is
fine; RAM oversubscription is not.

---

## 2. Provider matrix — and what changes between x86 and ARM

Vagrant drives whichever hypervisor you have. Pick the row that matches your machine.

| Host | Provider | Install | Notes |
|---|---|---|---|
| **Linux x86_64** | `libvirt` | `vagrant plugin install vagrant-libvirt` + `libvirt`, `qemu-kvm`, `virt-install` | The reference path. Fastest, and the only one where PXE, VirtualBMC and a serial console all behave exactly as on real hardware. |
| **Windows x86_64** | `virtualbox` | VirtualBox 7.x + Vagrant | Works. Disable Hyper-V, or VirtualBox falls back to a slow execution mode. |
| **Windows (alt.)** | `libvirt` inside WSL2 | Enable `nestedVirtualization=true` in `.wslconfig` | Closer to the reference path; more moving parts. |
| **macOS, Intel** | `virtualbox` | VirtualBox 7.x + Vagrant | Works. |
| **macOS, Apple Silicon** | `qemu` | `brew install qemu` + `vagrant plugin install vagrant-qemu`, then once `./qemu/make-box.sh` | **Recommended.** The only Apple Silicon path that PXE-boots diskless nodes (Module 04). Tested 29/09/2026: 4 VMs, cluster network, Module 01 deliverable, PXE nodes. See §2.1. |
| **macOS, Apple Silicon (alt.)** | `virtualbox` | VirtualBox **≥ 7.1** + Vagrant; the Extension Pack, if installed, must be the **same version** | Works for Modules 01–03 (Module 01 tested end to end). **No PXE**, so you would have to switch to `qemu` for Module 04. |

The Vagrantfile detects an ARM host and adjusts itself; you do not need to set anything. What it
changes, and what that means for the labs:

| | x86_64 host | ARM host (Apple Silicon) |
|---|---|---|
| Guest architecture | x86_64 | **aarch64** — the same ISA as Deucalion's A64FX nodes |
| Default box | `rockylinux/9` | QEMU: `fced/rockylinux-9-qemu` (built by `qemu/make-box.sh`); VirtualBox: `bento/rockylinux-9` (the official arm64 box is broken there) |
| Nested virtualisation | on | **off** (it crashes the VM on Apple Silicon) |
| Interface names | depend on box and provider (`eth0`/`eth1`, `enp0s3`/`enp0s8`, …) | `enp0s8` / `enp0s9` (QEMU and VirtualBox, tested) |
| CPU flags to look for (Module 01, 03) | `avx2`, `avx512*`, `fma` | `asimd` (NEON), `sve`, `sve2` — see the warning below |
| PXE, diskless nodes (Module 04) | works | **QEMU provider only** (§2.1, §4) |
| Everything else (Ansible, SLURM, EESSI, Apptainer, monitoring) | works | expected to work: EESSI, OpenHPC and Apptainer publish aarch64 builds; confirm as you reach each module |

> **Apple Silicon: SVE is advertised but not there.** `lscpu` inside the VM lists `sve2`, but an
> SVE instruction dies with *Illegal instruction*: Apple's cores execute SVE only in a special
> streaming mode the guest cannot use. Do not build with `-march=...+sve` for your VMs. On
> Deucalion's A64FX, SVE is real (512-bit), which is exactly the contrast Module 03 measures.

The one thing that is identical on every host is the one that matters most: the **cluster
network** `10.10.G.0/24`, with no DHCP from the hypervisor.

### 2.1 Apple Silicon with the QEMU provider

```bash
brew install qemu                       # also installs vde_switch
vagrant plugin install vagrant-qemu
cd lab-env && ./qemu/make-box.sh        # once: builds fced/rockylinux-9-qemu from Bento's arm64 box
export FCED_GROUP=07
vagrant up --provider qemu              # or: export VAGRANT_DEFAULT_PROVIDER=qemu
```

What is different from VirtualBox, and why:

- **The cluster network is a VDE switch** (`/tmp/fced-gNN.vde`), a user-space Ethernet switch that
  ships with Homebrew's QEMU. The Vagrantfile starts it; it needs no root. QEMU's own multicast
  networking does not deliver frames on macOS, and `vmnet` needs root.
- `vagrant up` prints *"You have configured private_network but advanced_network is not enabled"*:
  expected. The cluster NIC is added by the Vagrantfile itself and configured by a provisioner, with
  the same addresses as every other provider.
- **Fixed SSH ports** 50022–50025 (mgmt, store, node01, node02). `vagrant ssh` and `vagrant ssh-config`
  work as usual.
- There is no official Rocky 9 box for this provider (the `rockylinux/9` libvirt/arm64 download is
  gone), hence `make-box.sh`, which repackages Bento's image without changing it.
- `systemctl --failed` shows **`vboxadd.service` and `vboxadd-service.service`**: the image carries
  VirtualBox's guest additions, and there is no VirtualBox. That is a real failure to explain in
  Module 01, Task 4 — and to fix in your image later.

Set the box explicitly only if the default does not suit you:

```bash
export FCED_BOX=rockylinux/9          # x86_64 default
export FCED_BOX=bento/rockylinux-9    # ARM default; also has an x86_64 VirtualBox build (no libvirt)
```

---

## 3. First run

```bash
git clone <your group repository> && cd <repo>/lab-env
export FCED_GROUP=07                  # your group number; sets the 10.10.7.0/24 subnet

vagrant up                            # 10-20 minutes on the first run
vagrant status
vagrant ssh mgmt
```

`vagrant up` gives you four machines on `10.10.G.0/24`, where `G` is your group number:

| Host | RAM | vCPU | Address | Role |
|---|---|---|---|---|
| `mgmt` | 3 GB | 2 | `10.10.G.1` | Login, management, provisioning, scheduler, monitoring |
| `store` | 1 GB | 1 | `10.10.G.20` | Shared storage; carries a 40 GB data disk |
| `node01` | 2 GB | 2 | `10.10.G.101` | Compute |
| `node02` | 2 GB | 2 | `10.10.G.102` | Compute |

Each machine has two interfaces. The first is Vagrant's NAT interface — it is how your laptop reaches
the VM and how the VM reaches the internet. **Every VM has its own private NAT**, a small router inside
the hypervisor: all four get the same `10.0.2.15` on it (gateway `10.0.2.2`), and none can reach another
through it. Your laptop reaches each one on its own forwarded port (`vagrant ssh-config` shows which).
The second is the cluster network, and **the hypervisor's DHCP
server is deliberately switched off on it**, because from Module 04 Warewulf's `dhcpd` owns that
network. Two DHCP servers on one segment is the most common way to lose an afternoon here.

Their **names depend on the provider** (`enp0s8`/`enp0s9` on VirtualBox/ARM, `eth0`/`eth1` or
`ens*` elsewhere). Do not hard-code them; find the cluster interface by its address:

```bash
CIF=$(ip -o -4 addr show to 10.10.$FCED_GROUP.0/24 | awk '{print $2}')   # e.g. enp0s9
```

---

## 4. What changes in Module 04

Until Module 04, all four machines are ordinary Vagrant boxes with a disk installation. In Module 04
you make the compute nodes **stateless**: they get no operating system on disk and boot over the
network from Warewulf.

A machine with no OS has no box, so Vagrant can no longer describe it. From that point the compute
nodes are created directly against the hypervisor:

```bash
vagrant destroy node01 node02          # they stop being boxes
./nodes-pxe.sh create                  # and become diskless PXE machines
./nodes-pxe.sh start node01
./nodes-pxe.sh console node01          # watch it boot
```

`mgmt` and `store` stay under Vagrant, because they legitimately hold state.

> **ARM hosts (Apple Silicon): use the QEMU provider for this.** VirtualBox's ARM firmware has no
> network boot at all (*"No bootable option or device was found"*), so `nodes-pxe.sh` refuses it.
> With QEMU (§2.1) the same commands work: each node is a QEMU process on the cluster's VDE switch,
> with a fixed MAC and no disk. Homebrew's UEFI firmware has no network stack either, so the node
> starts **iPXE from a tiny read-only drive** that holds nothing else; iPXE then does DHCP, TFTP and
> HTTP exactly as a network card's boot ROM would. Tested 29/09/2026 with `dnsmasq` on `mgmt` handing
> out fixed addresses and an iPXE script (both nodes, plus `reset`/`stop`/`destroy`); **not yet with
> Warewulf itself**, whose `dhcpd` answers iPXE clients with its iPXE script in the same way. (Debian's `qemu-efi-aarch64` firmware does PXE natively, but hangs
> under Apple's hypervisor — tested with 2025.02 and 2026.08.) The console is `./nodes-pxe.sh
> console node01` (leave with Ctrl-C); `reset` and `stop` go through the QEMU monitor.

### There is no BMC on a laptop

Real compute nodes have a baseboard management controller: an independent computer that can power the
machine on, off, and show you its console when the operating system is dead. Your VMs do not have one.
**The hypervisor is the BMC here**, and `nodes-pxe.sh` is the `ipmitool` equivalent:

| Real hardware | Here |
|---|---|
| `ipmitool … power on/off/cycle` | `./nodes-pxe.sh start\|stop\|reset node01` |
| `ipmitool … sol activate` | `./nodes-pxe.sh console node01` |
| `ipmitool … chassis bootdev pxe` | boot order, set once at creation |

On a Linux host with libvirt you can go further and run **VirtualBMC** (`vbmc`) or the Redfish
emulator **sushy-tools**, which expose a real IPMI or Redfish endpoint in front of a libvirt domain.
Then `ipmitool -I lanplus …` works verbatim, exactly as in the lecture. Module 04 asks you to try it
if your host supports it.

---

## 5. If you only have 8 GB

```bash
export FCED_PROFILE=small     # mgmt 2.5 GB + node01 2 GB + store 1 GB
```

You get one compute node instead of two. Everything works except the things that genuinely need two
nodes: multi-node MPI (Module 08) and scheduling contention between jobs on different nodes
(Module 06). For those, pair up with another group in the lab session, or start `node02` temporarily
with everything else shut down.

Tell the teaching staff in week 1 if you are on the reduced profile, so the project expectations are
adjusted rather than discovered at the defence.

---

## 6. When it goes wrong

| Symptom | Cause, usually |
|---|---|
| `vagrant up` hangs at *"Waiting for machine to boot"* | Virtualisation disabled in firmware, or Hyper-V is holding the CPU on Windows. |
| Nodes get an address you did not configure | The hypervisor's DHCP is still on for the cluster network. Check `libvirt__dhcp_enabled: false` / `virtualbox__intnet`. |
| PXE boot never finds a server | Wrong network on the node's NIC, or `dhcpd` on `mgmt` is bound to `eth0` rather than `eth1`. |
| `VBOX_E_PLATFORM_ARCH_NOT_SUPPORTED` (Apple Silicon) | An x86 VM, or a box whose OVF describes one (`rockylinux/9` arm64). Use the default `bento/rockylinux-9`. |
| VM enters *Guru Meditation* right after "Booting VM" (Apple Silicon) | Nested virtualisation is on. The Vagrantfile turns it off on ARM hosts; check you have not re-added it. |
| `VERR_PDM_USB_NAME_CLASH` for every VM | The VirtualBox Extension Pack is a different version from VirtualBox. Install the matching pack, or remove it. |
| `ip addr show eth1`: *Device does not exist* | Interface names depend on the provider — see §3. |
| Everything is extremely slow | RAM is oversubscribed and the host is swapping. Close things, or use the reduced profile. |
| `vagrant ssh` stops working after Module 02 | Your SSH hardening removed the `vagrant` user or its key. Recover through the hypervisor console. |
| Node boots but has no `/apps` | `store` is not up, or its export is not configured yet. |

**Before hardening anything, know how to get back in.** `./nodes-pxe.sh console` and
`virsh console mgmt` (or the VirtualBox GUI) are your route into a machine whose network
configuration you have just broken. You will need it at least once.

---

## 7. Snapshots

Take one before anything destructive. It is much faster than a rebuild, and it costs you nothing.

```bash
vagrant snapshot save mgmt before-module-09
vagrant snapshot restore mgmt before-module-09
vagrant snapshot list
```

Snapshots are a convenience, not a strategy. Anything that matters must be reproducible from your
repository — that is what the project is graded on.
