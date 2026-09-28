use core.nu [fail]
const schemas = path self | path dirname

export def schema-for [version: string] {
  match $version {
    'codex-cli 0.154.0' => { open ($schemas | path join .. chats-schema.json) }
    'codex-cli 0.157.0' => { open ($schemas | path join schema-0.157.json) }
    _ => { fail $'Unsupported Codex version: ($version); add and validate its schema adapter first' }
  }
}
