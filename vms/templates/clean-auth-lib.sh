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

scrubs_runtime_auth_root() {
  runtime_user_dir="/run/user/$(id -u)"

  if [ -d "/dev/shm" ]; then
    printf '%s\n' "/dev/shm"
    return 0
  fi

  if [ -d "${runtime_user_dir}" ]; then
    printf '%s\n' "${runtime_user_dir}"
    return 0
  fi

  echo "scrubs clean auth: missing tmpfs runtime directory (/dev/shm or ${runtime_user_dir})" >&2
  return 1
}

scrubs_runtime_auth_dir() {
  runtime_root="$(scrubs_runtime_auth_root)" || return 1
  runtime_dir="${runtime_root}/scrubs-clean-auth"

  umask 077
  mkdir -p "${runtime_dir}"
  chmod 700 "${runtime_dir}"
  printf '%s\n' "${runtime_dir}"
}

scrubs_materialize_runtime_secret() {
  ciphertext_path="$1"
  runtime_path="$2"
  runtime_tmp="${runtime_path}.tmp.$$"

  if [ -f "${runtime_path}" ] \
    && [ "${runtime_path}" -nt "${ciphertext_path}" ] \
    && [ "${runtime_path}" -nt "${scrubs_clean_auth_key}" ]; then
    return 0
  fi

  if ! scrubs_decrypt_clean_secret "${ciphertext_path}" > "${runtime_tmp}"; then
    rm -f "${runtime_tmp}"
    return 1
  fi

  chmod 600 "${runtime_tmp}"
  mv "${runtime_tmp}" "${runtime_path}"
}
