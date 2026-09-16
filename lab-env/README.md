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

## 2. Provider matrix

Vagrant drives whichever hypervisor you have. Pick the row that matches your machine.

| Host | Provider | Install | Notes |
|---|---|---|---|
| **Linux** | `libvirt` | `vagrant plugin install vagrant-libvirt` + `libvirt`, `qemu-kvm`, `virt-install` | The reference path. Fastest, and the only one where PXE, VirtualBMC and a serial console all behave exactly as on real hardware. |
| **Windows** | `virtualbox` | VirtualBox 7.x + Vagrant | Works. Disable Hyper-V, or VirtualBox falls back to a slow execution mode. |
| **Windows (alt.)** | `libvirt` inside WSL2 | Enable `nestedVirtualization=true` in `.wslconfig` | Closer to the reference path; more moving parts. |
| **macOS, Intel** | `virtualbox` | VirtualBox 7.x + Vagrant | Works. |
| **macOS, Apple Silicon** | `qemu` | `vagrant plugin install vagrant-qemu`, plus an **aarch64** box | See the warning below. |

> **Apple Silicon — read this before the first lab.** VirtualBox does not run on ARM Macs. The
> `vagrant-qemu` provider does, but you need an aarch64 box for your distribution, and the whole
> stack (OpenHPC, Warewulf, EasyBuild, EESSI) must then be the aarch64 build of itself. EESSI and
> OpenHPC both publish aarch64, so this is expected to work — but **verify it in week 1**, not in
> week 11. If it does not, tell the teaching staff early: the fallbacks are UTM with a manually
> created Linux VM, a lab-room machine, or a small cloud instance.

Set your box explicitly if the default is not right for your architecture:

```bash
export FCED_BOX=rockylinux/9          # x86_64 default
export FCED_BOX=<an aarch64 box>      # Apple Silicon
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

Each machine has two interfaces. `eth0` is Vagrant's NAT interface — it is how your laptop reaches
the VM and how the VM reaches the internet. `eth1` is the cluster network, and **the hypervisor's DHCP
server is deliberately switched off on it**, because from Module 04 Warewulf's `dhcpd` owns that
network. Two DHCP servers on one segment is the most common way to lose an afternoon here.

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
