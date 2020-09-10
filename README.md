# play-with-coreos
This project is created to build, run and test CoreOS. It's just for learning.  
It's tested on Centos8, and Fedora32. Not recommend for Ubuntu Distribution since SELinux is used.

A demo of the start and destroy of a CoreOS VM can be found here: [README.md Demo section](#demo).

<!-- TOC depthFrom:2 depthTo:6 withLinks:1 updateOnSave:1 orderedList:0 -->

- [Prerequisites](#prerequisites)
- [Hardware Requirements](#hardware-requirements)
- [Quickstart](#quickstart)
- [Usage](#usage)
- [Troubleshooting](#Troubleshooting)
- [Demo](#demo)
  - [Start FCOS qcow2 VM](#start-fcos-qcow2-vm)
  - [Running etcd container](#running-etcd-container)
  - [Destroy VM](#destroy-vm)
- [Creating an Issue](#creating-an-issue)

<!-- /TOC -->

## Prerequisites
* `make`
* `virt-install`
* `Container Runtime`: Podman or Docker
* `libvirt`
* `SELinux`: Enforcing

## Hardware Requirements

* Virtualization Support
```shell
$ egrep '^flags.*(vmx|svm)' /proc/cpuinfo
```
If this command resuls in nothing printed, your system does not support the relevant virtualization extensions. You can still use QEMU/KVM, but the emulator will fall back to software virtualization, which is much slower. (`--virt-type=qemu`)

* KVM kernel module
To verify that the KVM kernel modules are properly loaded:
```shell
$ lsmod | grep kvm
```
If this command lists kvm_intel or kvm_amd, KVM is properly configured.

## Quickstart
To start with the defaults, run the following:
```shell
$ make coreos
```

To start with customized variables:
```shell
$ NAME=vm-1 CPU=4 MEMORY=4096 DISK=2 IMAGE=/path/to/imgage YAML=/path/to/ignition.yaml make coreos
```

To Destroy:
```shell
$ make destroy
```

## Usage
Run `make help` to see available commands.
```shell
Usage: make [TARGET ...]

check-cont-runt                To check which container runtime is used
check-virt                     To check whether system has a CPU with virtualization support
clean                          Remove Ignition files
destroy                        Destroy VM
download-fcos-iso              Download Fedora CoreOS ISO image
download-fcos-pxe              Download Fedora CoreOS PXE kernel
download-fcos-qcow2            Download Fedora CoreOS qcow2 image
fcos-qcow2-autologin           Create Fedora CoreOS from qcow2 image - test autologin
fcos-qcow2-container           Create Fedora CoreOS from qcow2 image - test create container
fcos-qcow2-service             Create Fedora CoreOS from qcow2 image - test systemd service
help                           Show this help menu.
list                           List of Virtual Machines created by virsh-install
prerequisite                   Run check prerequisite
pull-all                       Pull all required images
pull-coreos-installer          Pull coreor-installer image
pull-fcct                      Pull fcct (Fedora CoreOS Config Transpiler) image
pull-ignition                  Pull Ignition image
run                            Create and Run CoreOS VM
status                         Status of Virtual Machines created by virsh-install
validate-ign                   Verifying Ignition config format is valid
yml2ign                        Convert configuation YAML file to IGN file
```
[Note] To escape out of the serial console, press `CTRL + ]`

## Troubleshooting

### ioctl(KVM_CREATE_VM) failed: 16 Device or resource busy
This is caused by the virtualization technology is being locked by another hypervisor (ex: VirtualBox). To solved this problem, we just turn off running VirtualBox instance or run `virt-install` with option `--virt-type=qemu`. If closing VirtualBox doesn't fix it, you can stop the driver service with `sudo systemctl stop vboxdrv`.

## Demo

### Start FCOS qcow2 VM
[![asciicast](https://asciinema.org/a/ix5vxtBvhWi69HiDnEotB5Jpe.svg)](https://asciinema.org/a/ix5vxtBvhWi69HiDnEotB5Jpe)

### Running etcd container
[![asciicast](https://asciinema.org/a/I1bnSGUsReq74etuCqvlnD2cz.svg)](https://asciinema.org/a/I1bnSGUsReq74etuCqvlnD2cz)

### Destroy VM
[![asciicast](https://asciinema.org/a/ZDdNgLKdPc2m4oO1RKHeVyQ6K.svg)](https://asciinema.org/a/ZDdNgLKdPc2m4oO1RKHeVyQ6K)
