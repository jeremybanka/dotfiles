export def repo-root [] {
  $env.FILE_PWD | path dirname
}

export def scrubs-dir [] {
  repo-root | path join "scrubs"
}

export def load-settings [] {
  let settings_file = (scrubs-dir | path join "settings.env")

  if not ($settings_file | path exists) {
    return {}
  }

  open --raw $settings_file
  | lines
  | each {|line| $line | str trim }
  | where {|line| $line != "" and not ($line | str starts-with "#") }
  | reduce --fold {} {|line, acc|
      let parsed = ($line | parse --regex '^(?P<key>[A-Za-z_][A-Za-z0-9_]*)=(?P<value>.*)$')
      if ($parsed | is-empty) {
        $acc
      } else {
        let entry = ($parsed | first)
        let raw_value = ($entry.value | str trim)
        let value = if (
          ($raw_value | str length) >= 2
          and (
            (($raw_value | str starts-with '"') and ($raw_value | str ends-with '"'))
            or (($raw_value | str starts-with "'") and ($raw_value | str ends-with "'"))
          )
        ) {
          $raw_value | str substring 1..-1
        } else {
          $raw_value
        }
        $acc | upsert $entry.key $value
      }
    }
}

export def get-setting [
  settings: record
  key: string
  default_value: any = null
] {
  if ($env | columns | any {|column| $column == $key }) {
    $env | get $key
  } else if ($settings | columns | any {|column| $column == $key }) {
    $settings | get $key
  } else {
    $default_value
  }
}

export def expand-home [value: string] {
  if $value == "" {
    ""
  } else if ($value | str starts-with "~/") {
    $env.HOME | path join ($value | str replace --regex '^~/' "")
  } else if ($value | str starts-with "$HOME/") {
    $env.HOME | path join ($value | str replace --regex '^\$HOME/' "")
  } else if ($value | str starts-with "${HOME}/") {
    $env.HOME | path join ($value | str replace --regex '^\$\{HOME\}/' "")
  } else {
    $value
  }
}

export def is-url [value: string] {
  not (($value | parse --regex '^(?P<scheme>[A-Za-z][A-Za-z0-9+.-]*)://.*$') | is-empty)
}
