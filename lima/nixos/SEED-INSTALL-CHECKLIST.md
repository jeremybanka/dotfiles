# Seed Install Checklist

Use this inside the NixOS ARM installer VM after `seed.sh` has booted the
installer.

## 1. Become root and verify the seed share

```sh
sudo -i
mkdir -p /mnt/host-scrubs-seed
mount -t 9p -o trans=virtio,version=9p2000.L,ro lima-731933a41aaf93b5 /mnt/host-scrubs-seed || true
ls -la /mnt/host-scrubs-seed
```

You should see:

- `base.nix`
- `install.sh`

## 2. Partition and format the disk

```sh
parted --script /dev/vda -- \
  mklabel gpt \
  mkpart ESP fat32 1MiB 512MiB \
  set 1 esp on \
  mkpart primary ext4 512MiB 100%

udevadm settle
mkfs.fat -F 32 -n ESP /dev/vda1
mkfs.ext4 -F -L nixos /dev/vda2
```

## 3. Mount the target system

```sh
mount /dev/vda2 /mnt
mkdir -p /mnt/boot
mount /dev/vda1 /mnt/boot
nixos-generate-config --root /mnt
```

If `mkdir -p /mnt/boot` says it already exists, that is fine.

## 4. Copy `base.nix` through `/tmp`

Mounting `/mnt` hides `/mnt/host-scrubs-seed`, so briefly unmount the target
root, copy `base.nix` to `/tmp`, then remount the target system.

```sh
umount /mnt/boot
umount /mnt
cp /mnt/host-scrubs-seed/base.nix /tmp/scrubs-seed-base.nix
mount /dev/vda2 /mnt
mkdir -p /mnt/boot
mount /dev/vda1 /mnt/boot
cp /tmp/scrubs-seed-base.nix /mnt/etc/nixos/scrubs-seed-base.nix
```

## 5. Replace the installed config

```sh
cat > /mnt/etc/nixos/configuration.nix <<'EOF'
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./scrubs-seed-base.nix
  ];
}
EOF
```

## 6. Install NixOS

```sh
nixos-install --no-root-passwd
```

## 7. Shut the VM down

```sh
shutdown now
```

## 8. Export the base image on macOS

After the VM shuts down, run this on the Mac:

```sh
/Users/jem/dotfiles/lima/nixos/export-seed-image.sh scrubs-seed-2 /absolute/path/to/nixos-base-aarch64.qcow2
```

## Notes

- This flow uses the updated ARM EFI path with `systemd-boot`.
- Do not add the old GRUB device override from the earlier failed attempt.
