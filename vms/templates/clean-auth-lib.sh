#!/bin/sh
set -eu

scrubs_clean_auth_dir="${HOME}/.local/share/scrubs/clean-auth"
scrubs_clean_auth_key="${scrubs_clean_auth_dir}/seal-key"
scrubs_clean_auth_openssl="/run/current-system/sw/bin/openssl"

scrubs_clean_secret_path() {
  printf '%s/%s\n' "${scrubs_clean_auth_dir}" "$1"
}

scrubs_has_clean_secret() {
  [ -f "$1" ] && [ -f "${scrubs_clean_auth_key}" ]
}

scrubs_decrypt_clean_secret() {
  ciphertext_path="$1"

  if [ ! -f "${ciphertext_path}" ]; then
    echo "scrubs clean auth: missing sealed secret at ${ciphertext_path}" >&2
    return 1
  fi

  if [ ! -f "${scrubs_clean_auth_key}" ]; then
    echo "scrubs clean auth: missing seal key at ${scrubs_clean_auth_key}" >&2
    return 1
  fi

  if [ ! -x "${scrubs_clean_auth_openssl}" ]; then
    echo "scrubs clean auth: missing openssl at ${scrubs_clean_auth_openssl}" >&2
    return 1
  fi

  "${scrubs_clean_auth_openssl}" enc -d -aes-256-cbc -pbkdf2 \
    -pass "file:${scrubs_clean_auth_key}" \
    -in "${ciphertext_path}"
}
