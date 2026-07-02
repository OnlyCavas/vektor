#!/usr/bin/env bash
set -euo pipefail

# mkdir -p /root/host
# mount -t 9p -o trans=virtio,version=9p2000.L host /root/host

ISO="./assets/artix-base-dinit-20260402-x86_64.iso"
DISK="./assets/artix-target.qcow2"
OVMF_VARS="./assets/ovmf_vars.fd"

OVMF_CODE="/usr/share/edk2/ovmf/OVMF_CODE.fd"
OVMF_VARS_SRC="/usr/share/edk2/ovmf/OVMF_VARS.fd"

zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe

[ -f "$DISK" ] || qemu-img create -f qcow2 "$DISK" 40G

[ -f "$OVMF_VARS" ] || cp "$OVMF_VARS_SRC" "$OVMF_VARS"

qemu-system-x86_64 \
  -enable-kvm -cpu host -smp 4 -m 4G \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$DISK",if=virtio \
  -cdrom "$ISO" -boot menu=on \
  -virtfs local,path="$PWD/zig-out/bin",mount_tag=host,security_model=none \
  -net nic -net user
