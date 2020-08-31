# Bash is required as the shell
SHELL := /bin/bash
OS := $(shell { . /etc/os-release && echo $${ID}; })
DIST := $(shell { . /etc/os-release && echo $${VERSION_ID}; })
VIRT_INS := $(shell command -v virt-install)
VIRTD_STATE := $(shell systemctl is-active libvirtd)
CntRt := $(shell { command -v podman || command -v docker; })

CoreOS_INST_IMG ?= quay.io/coreos/coreos-installer:release
FCCT_IMG ?= quay.io/coreos/fcct:release
IGNITION_IMG ?= quay.io/coreos/ignition-validate:release

NAME ?= fcos
CPU ?= 2
MEMORY ?= 2048#MB
DISK ?= 10#GB

CoreOS_Installer := $(CntRt) run --pull=missing           \
 				   --rm --tty --interactive             \
 				   --security-opt label=disable         \
 				   --volume $${PWD}:/pwd --workdir /pwd \
 				   quay.io/coreos/coreos-installer:release
Ignition_Validate := $(CntRt) run --rm --tty --interactive    \
 					--security-opt label=disable             \
 					--volume $${PWD}:/pwd --workdir /pwd      \
 					quay.io/coreos/ignition-validate:release
FCCT := $(CntRt) run --rm --tty --interactive    \
					--security-opt label=disable        \
					--volume $${PWD}:/pwd --workdir /pwd \
					quay.io/coreos/fcct:release

check-virt: ## To check whether system has a CPU with virtualization support
	@echo "Checking Virtualization support..."
	@egrep '^flags.*(vmx|svm)' /proc/cpuinfo &> /dev/null && \
		echo "[OK] Virtualization support!" || \
		{ echo "[NOT] Your system does NOT support Virtualization."; exit 1; }
	@echo "Verifying KVM kernel modules are properly loaded..."
	@lsmod | grep kvm &>/dev/null && \
		echo "[OK] KVM kernel modules are configured." || \
		{ echo "[NOT] KVM kernel modules are NOT configured!"; exit 1; }
	@echo

prerequisite: check-virt ## Run check prerequisite
	@echo "=== PreRequisite ==="
	@echo "[O] make: $$(command -v make)"
	@[ -x "`which virt-install 2>/dev/null`" ] && \
		echo "[O] virt-install: $$(command -v virt-install)" || \
		echo "[X] virt-install: is NOT installed!"
	@[ -x "`which podman 2>/dev/null`" ] && \
		echo "[O] podman: $$(command -v podman)" || \
		echo "[X] podman: is NOT installed!"
	@[ -x "`which docker 2>/dev/null`" ] && \
		echo "[O] docker: $$(command -v docker)" || \
		echo "[X] docker: is NOT installed!"
	@[ "$(VIRTD_STATE)" = "active" ] && \
		echo "[O] 'libvirtd' service is active." || \
		echo "[X] 'libvirtd' service is NOT active"
	@groups | grep libvirt &>/dev/null && \
		echo "[O] user ($${USER}) is in 'libvirt' group." || \
		echo "[X] user ($${USER}) is NOT in 'libvirt' group!"
	@[ "$(shell getenforce)" != "Disable" ] && \
		echo "[O] SELinux status: `getenforce`" || \
		echo "[X] SELinux status: `getenforce`"
	@echo "===================="
	@echo "[NOTE] Press CTRL + ] to escape out of the serial console."
	@echo "===================="

container-runtime: ## Get container runtime candidate
ifndef CntRt
	$(error "[ERROR] Container Runtime (podman or docker) is NOT installed!")
endif

pull-coreos-installer: container-runtime ## Pull coreor-installer image
	@$(CntRt) image exists $(CoreOS_INST_IMG) && \
		echo "[INFO] '$(CoreOS_INST_IMG)' already exists." || \
		$(CntRt) pull $(CoreOS_INST_IMG)

pull-fcct: container-runtime ## Pull fcct (Fedora CoreOS Config Transpiler) image
	@$(CntRt) image exists $(FCCT_IMG) && \
		echo "[INFO] '$(FCCT_IMG)' already exists." || \
		$(CntRt) pull $(FCCT_IMG)

pull-ignition: container-runtime ## Pull Ignition image
	@$(CntRt) image exists $(IGNITION_IMG) && \
		echo "[INFO] '$(IGNITION_IMG)' already exists." || \
		$(CntRt) pull $(IGNITION_IMG)

pull-all: pull-coreos-installer pull-fcct pull-ignition ## Pull all required images

download-fcos-qcow2: pull-coreos-installer ## Download Fedora CoreOS qcow2 image
	@$(CoreOS_Installer) download -p qemu -f qcow2.xz --decompress

download-fcos-iso: pull-coreos-installer ## Download Fedora CoreOS ISO image
	@$(CoreOS_Installer) download -f iso

download-fcos-pxe: pull-coreos-installer ## Download Fedora CoreOS PXE kernel
	@$(CoreOS_Installer) download -f pxe

fcos-qcow2-autologin: prerequisite pull-all ## Create Fedora CoreOS from qcow2 image - test autologin
	@test -f fedora-coreos*.qcow2 || \
		{ echo "Downloading qcow2 image..."; make download-fcos-qcow2; }
	$(eval IMG := $(shell find $${PWD} -type f -name fedora-coreos*.qcow2 | tail -1))
	$(eval YAML := ignition/fcct-autologin.yaml)
	$(eval IGN := ignition/autologin.ign)
	$(MAKE) start-vm

fcos-qcow2-service: prerequisite pull-all ## Create Fedora CoreOS from qcow2 image - test systemd service
	@test -f fedora-coreos*.qcow2 || \
		{ echo "Downloading qcow2 image..."; make download-fcos-qcow2; }
	$(eval IMG := $(shell find $${PWD} -type f -name fedora-coreos*.qcow2 | tail -1))
	$(eval YAML := ignition/fcct-services.yaml)
	$(eval IGN := ignition/services.ign)
	$(MAKE) start-vm

fcos-qcow2-container: prerequisite pull-all ## Create Fedora CoreOS from qcow2 image - test create container
	@test -f fedora-coreos*.qcow2 || \
		{ echo "Downloading qcow2 image..."; make download-fcos-qcow2; }
	$(eval IMG := $(shell find $${PWD} -type f -name fedora-coreos*.qcow2 | tail -1))
	$(eval YAML := ignition/fcct-containers.yaml)
	$(eval IGN := ignition/containers.ign)
	$(MAKE) start-vm

start-vm:
	@test -f $(YAML) || \
		{ echo "[ERROR] $${YAML} does NOT exist!"; exit 1; }
	@echo "Converting configuration file into an Ignition config..."
	@$(FCCT) --pretty --strict $(YAML) --output $(IGN)
	@echo "Verifying Ignition config format is valid..."
	@$(Ignition_Validate) $(IGN) && \
		echo "[Success] Ignition config is created successfully." || \
		{ echo "[Fail] Ignition config is NOT created successfully!"; exit 1; }
	@echo
	@echo "Booting Fedora CoreOS..."
	@# Setup the correct SELinux label to allow access to the config
	chcon --verbose --type svirt_home_t $(IGN)
	@# Start a Fedora CoreOS virtual machine
	$(VIRT_INS) --name=$(NAME) --vcpus=$(CPU) --ram=$(MEMORY) \
		--os-variant=$(OS)$(DIST) --disk=size=$(DISK),backing_store=$(IMG) \
		--import --network=bridge=virbr0 --graphics=none \
		--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=$${PWD}/$(IGN)"

destroy: ## Destroy VM 
	@virsh destroy $(NAME) || \
		{ \
		echo "==================================="; \
		echo "run 'make list' to see domain name"; \
		echo "[USAGE]: NAME=<name> make destroy"; \
		echo "==================================="; \
		exit 1; \
		}
		
	@virsh undefine --remove-all-storage $(NAME)

list: ## List of Virtual Machines created by virsh-install
	@virsh list

tmp:
ifneq ($(VIRTD_STATE),active)
	$(error not active)
else
	$(info $(VIRTD_STATE))
endif
ifndef TMP
	$(error $(TMP)"tmp")
else
	$(info "ok"$(TMP))
endif
ifneq ("$(wildcard /etc/os-release)","")
	$(info $(wildcard /etc/os-release))
	$(info nnnn)
else
	$(info $(wildcard /etc/os-release))
	$(info kkkk)
endif
ifneq ("$(wildcard ./ignition/*.ign)", "")
	$(info Exist $(DIR))
else
	$(info NO)
endif
	@echo "OS: $(OS)"
	@echo "DIST: $(DIST)"


help: ## Show this help menu.
	@echo "Usage: make [TARGET ...]"
	@echo
	@grep -E '^[0-9a-zA-Z_%-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
.EXPORT_ALL_VARIABLES:
.PHONY: help \
	check-virt container-runtime \
	destroy \
	download-fcos-iso download-fcos-pxe download-qcow2 \
	fcos-qcow2-autologin fcos-qcow2-container fcos-qcow2-service \
	list \
	prerequisites \
	pull-all pull-coreos-installer pull-fcct pull-ignition
