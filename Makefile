# Bash is required as the shell
SHELL := /bin/bash
OS := $(shell { . /etc/os-release && echo $${ID}; })
DIST := $(shell { . /etc/os-release && echo $${VERSION_ID}; })
VIRT_INS := $(shell command -v virt-install)
VIRTD_STATE := $(shell systemctl is-active libvirtd)
CntRt := $(shell { command -v podman || command -v docker; })

CoreOS_INST_IMAGE ?= quay.io/coreos/coreos-installer:release
FCCT_IMAGE ?= quay.io/coreos/fcct:release
IGNITION_IMAGE ?= quay.io/coreos/ignition-validate:release

NAME ?= fcos
CPU ?= 2
MEMORY ?= 2048#MB
DISK ?= 10#GB

YAML ?= ignition/fcct-autologin.yaml
IGN ?= $(YAML:.yaml=.ign)
IMAGE ?=

ifdef CntRt
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
endif

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
	@echo

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

check-cont-runt: ## To check which container runtime is used
ifndef CntRt
	$(error "[ERROR] Container Runtime (podman or docker) is NOT installed!")
endif
	$(info "[INFO] Container Runtime : $(CntRt)")

pull-coreos-installer: check-cont-runt ## Pull coreor-installer image
	@$(CntRt) image exists $(CoreOS_INST_IMAGE) && \
		echo "[INFO] '$(CoreOS_INST_IMAGE)' already exists." || \
		$(CntRt) pull $(CoreOS_INST_IMAGE)

pull-fcct: check-cont-runt ## Pull fcct (Fedora CoreOS Config Transpiler) image
	@$(CntRt) image exists $(FCCT_IMAGE) && \
		echo "[INFO] '$(FCCT_IMAGE)' already exists." || \
		$(CntRt) pull $(FCCT_IMAGE)

pull-ignition: check-cont-runt ## Pull Ignition image
	@$(CntRt) image exists $(IGNITION_IMAGE) && \
		echo "[INFO] '$(IGNITION_IMAGE)' already exists." || \
		$(CntRt) pull $(IGNITION_IMAGE)

pull-all: pull-coreos-installer pull-fcct pull-ignition ## Pull all required images

download-fcos-qcow2: pull-coreos-installer ## Download Fedora CoreOS qcow2 image
	@$(CoreOS_Installer) download -p qemu -f qcow2.xz --decompress

download-fcos-iso: pull-coreos-installer ## Download Fedora CoreOS ISO image
	@$(CoreOS_Installer) download -f iso

download-fcos-pxe: pull-coreos-installer ## Download Fedora CoreOS PXE kernel
	@$(CoreOS_Installer) download -f pxe

fcos-qcow2-service: YAML = ignition/fcct-autologin.yaml
fcos-qcow2-autologin: coreos ## Create Fedora CoreOS from qcow2 image - test autologin

fcos-qcow2-service: YAML = ignition/fcct-services.yaml
fcos-qcow2-service: coreos ## Create Fedora CoreOS from qcow2 image - test systemd service

fcos-qcow2-container: YAML = ignition/fcct-containers.yaml
fcos-qcow2-container: coreos ## Create Fedora CoreOS from qcow2 image - test create container

yml2ign: pull-fcct ## Convert configuation YAML file to IGN file
ifndef YAML
	$(info [usage]: $$ YAML=/path/to/yaml make yaml2ign)
	$(error Please provide YAML file)
endif
ifndef IGN
	$(eval IGN := $(YAML:.yaml=.ign))
endif
	@test -f $(YAML) || \
		{ echo "[ERROR] $${YAML} does NOT exist!"; exit 1; }
	$(info [INFO] Converting configuration file into an Ignition config...)
	@$(FCCT) --pretty --strict $(YAML) --output $(IGN)
	$(info [INFO] Converted '$(YAML)' to '$(IGN)' successfully.)

validate-ign: pull-ignition ## Verifying Ignition config format is valid
ifndef IGN
	$(info [usage]: $$ IGN=/path/to/ign make validate-ign)
	$(error Please provide IGN file)
endif
	$(info [INFO] Verifying Ignition config format is valid...)
	@$(Ignition_Validate) $(IGN) && \
		echo "[INFO] '$(IGN)' is valid and ready to use." || \
		{ echo "[ERROR] '$(IGN)' is NOT valid!"; exit 1; }

get-image:
ifndef IMAGE
ifeq ("$(wildcard fedora-coreos*.qcow2)", "")
	$(info Downloading Fedora CoreOS qcow2 image (stable)...)
	@$(MAKE) download-fcos-qcow2 --no-print-directory
endif
endif

coreos: prerequisite yml2ign validate-ign get-image ## Create CoreOS VM
ifndef VIRT_INS
	$(error NOT found command '$(VIRT_INS)')
endif
ifndef IMAGE
	$(eval IMAGE := $(shell find $${PWD} -type f -name fedora-coreos*.qcow2 | tail -1))
else
	$(eval IMAGE := $(shell realpath $${IMAGE}))
endif
	@test -f $(IMAGE) || { echo "[ERROR] Image '$(IMAGE)' NOT Found!"; exit 1; }
	@test -f $(IGN) || { echo "[ERROR] Ignition '$(IGN)' NOT Found!"; exit 1; }
	@# Setup the correct SELinux label to allow access to the config
	@chcon --verbose --type svirt_home_t $(IGN) &> /dev/null
	$(info ============VM INFO============)
	$(info NAME     : $(NAME))
	$(info CPU      : $(CPU))
	$(info MEMORY   : $(MEMORY)MB)
	$(info DISK     : $(DISK)GB)
	$(info NETWORK  : bridge=virbr0)
	$(info GRAPHICS : none)
	$(info IMAGE    : $(IMAGE))
	$(info IGNITION : $(IGN))
	$(info ===============================)
	@$(VIRT_INS) --name=$(NAME) --vcpus=$(CPU) --ram=$(MEMORY) \
		--os-variant=$(OS)$(DIST) --disk=size=$(DISK),backing_store=$(IMAGE) \
		--import --network=bridge=virbr0 --graphics=none \
		--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=$${PWD}/$(IGN)"

list: ## List of Virtual Machines created by virsh-install
	@virsh list

status: list ## Status of Virtual Machines created by virsh-install

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

clean: ## Remove Ignition files
	rm ignition/*.ign

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
	check-cont-runt check-virt clean coreos\
	destroy \
	download-fcos-iso download-fcos-pxe download-qcow2 \
	fcos-qcow2-autologin fcos-qcow2-container fcos-qcow2-service \
	list \
	prerequisites \
	pull-all pull-coreos-installer pull-fcct pull-ignition \
	status \
	validate-ign \
	yml2ign
