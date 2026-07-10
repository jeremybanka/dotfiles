#!/run/current-system/sw/bin/nu

const real_codex = "/run/current-system/sw/bin/codex"
const openssl_bin = "/run/current-system/sw/bin/openssl"
const tar_bin = "/run/current-system/sw/bin/tar"
const chmod_bin = "/run/current-system/sw/bin/chmod"
const ln_bin = "/run/current-system/sw/bin/ln"

def fail [message: string] {
  error make { msg: $message }
}

def run-chmod [mode: string, path: string] {
  let result = (^$chmod_bin $mode $path | complete)
  if $result.exit_code != 0 {
    fail $"scrubs codex wrapper: failed to chmod ($mode) ($path)"
  }
}

def copy-legacy-runtime-codex-home [legacy_codex_home: string, durable_codex_home: string] {
  if not ($legacy_codex_home | path exists) or $legacy_codex_home == $durable_codex_home {
    return
  }

  let result = (
    do {
      ^$tar_bin --directory $legacy_codex_home --create --file - --exclude ./auth.json .
      | ^$tar_bin --directory $durable_codex_home --extract --file -
    }
    | complete
  )

  if $result.exit_code != 0 {
    fail "scrubs codex wrapper: failed to migrate legacy runtime Codex state"
  }
}

def runtime-auth-dir [] {
  let runtime_root = if ("/dev/shm" | path exists) {
    "/dev/shm"
  } else {
    let uid_result = (^/run/current-system/sw/bin/id -u | complete)
    if $uid_result.exit_code != 0 {
      fail "scrubs clean auth: failed to resolve the current user ID"
    }

    let runtime_user_dir = $"/run/user/($uid_result.stdout | str trim)"
    if not ($runtime_user_dir | path exists) {
      fail $"scrubs clean auth: missing tmpfs runtime directory (/dev/shm or ($runtime_user_dir))"
    }

    $runtime_user_dir
  }

  let runtime_dir = ($runtime_root | path join "scrubs-clean-auth")
  mkdir $runtime_dir
  run-chmod "700" $runtime_dir
  $runtime_dir
}

def modified-at [path: string] {
  ls --directory $path | get 0.modified
}

def materialize-runtime-secret [ciphertext_path: string, key_path: string, runtime_path: string] {
  if (
    ($runtime_path | path exists)
    and (modified-at $runtime_path) > (modified-at $ciphertext_path)
    and (modified-at $runtime_path) > (modified-at $key_path)
  ) {
    return
  }

  let runtime_tmp = $"($runtime_path).tmp.($nu.pid)"
  rm -f $runtime_tmp

  let decrypt_result = (
    ^$openssl_bin enc -d -aes-256-cbc -pbkdf2
      -pass $"file:($key_path)"
      -in $ciphertext_path
      -out $runtime_tmp
    | complete
  )

  if $decrypt_result.exit_code != 0 {
    rm -f $runtime_tmp
    fail "scrubs codex wrapper: failed to materialize the sealed auth bundle"
  }

  run-chmod "600" $runtime_tmp
  mv -f $runtime_tmp $runtime_path
}

def --wrapped main [...args: string] {
  if not ($real_codex | path exists) {
    fail $"scrubs codex wrapper: missing real codex binary at ($real_codex)"
  }

  let guest_codex_home = ($env.HOME | path join ".codex")
  let configured_codex_home = ($env.CODEX_HOME? | default "")
  let normalized_codex_home = ($configured_codex_home | str trim --right --char "/")

  if (
    (($env.OPENAI_API_KEY? | default "") != "")
    or (($env.CODEX_ACCESS_TOKEN? | default "") != "")
    or ($configured_codex_home != "" and $normalized_codex_home != $guest_codex_home)
  ) {
    exec $real_codex ...$args
  }

  let clean_auth_dir = ($env.HOME | path join ".local" "share" "scrubs" "clean-auth")
  let ciphertext_path = ($clean_auth_dir | path join "codex-auth.json.enc")
  let key_path = ($clean_auth_dir | path join "seal-key")

  if not ($ciphertext_path | path exists) or not ($key_path | path exists) {
    exec $real_codex ...$args
  }

  umask rwx------ | ignore

  let runtime_auth_dir = (runtime-auth-dir)
  let runtime_auth_json = ($runtime_auth_dir | path join "codex-auth.json")
  let legacy_runtime_codex_home = ($runtime_auth_dir | path join "codex-home")
  let guest_auth_json = ($guest_codex_home | path join "auth.json")

  mkdir $guest_codex_home
  run-chmod "700" $guest_codex_home

  copy-legacy-runtime-codex-home $legacy_runtime_codex_home $guest_codex_home
  materialize-runtime-secret $ciphertext_path $key_path $runtime_auth_json

  let auth_bundle = try {
    open --raw $runtime_auth_json | from json
  } catch {
    fail "scrubs codex wrapper: runtime auth bundle is not valid JSON"
  }

  if (($auth_bundle.auth_mode? | default "") != "chatgpt") {
    fail "scrubs codex wrapper: runtime auth bundle is not using ChatGPT auth mode"
  }

  let link_result = (^$ln_bin -snf $runtime_auth_json $guest_auth_json | complete)
  if $link_result.exit_code != 0 {
    fail $"scrubs codex wrapper: failed to link auth into ($guest_auth_json)"
  }

  exec $real_codex ...$args
}
