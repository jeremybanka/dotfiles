set shell := ["zsh", "-cu"]

default:
  @just --list

bootstrap base_image instance_name="scrubs-dev":
  nu ./scrubs/bootstrap.nu {{base_image}} {{instance_name}}

download-latest-iso channel="nixos-25.11":
  nu ./scrubs/download-latest-iso.nu {{channel}}

export-seed-image instance_name output_path:
  nu ./scrubs/export-seed-image.nu {{instance_name}} {{output_path}}

refresh-base-image source_image="./scrubs/qcow2/scrubs.qcow2" output_path="" instance_name="scrubs-refresh":
  nu ./scrubs/refresh-base-image.nu {{source_image}} {{output_path}} {{instance_name}}

seed instance_name="scrubs-seed":
  nu ./scrubs/seed.nu {{instance_name}}

vm-shell instance_name:
  ./scripts/lima-shell.sh {{instance_name}}

sync-base-image-to-icloud image="scrubs-linux-lts.qcow2":
  nu ./scrubs/sync-base-image-to-icloud.nu {{image}}

sync-base-image-from-icloud image="scrubs-linux-lts.qcow2":
  nu ./scrubs/sync-base-image-from-icloud.nu {{image}}
