$env.PATH = ($env.PATH | split row (char esep) | where { $in != "/Users/jem/Library/Application Support/carapace/bin" } | prepend "/Users/jem/Library/Application Support/carapace/bin")

def --env get-env [name] { $env | get $name }
def --env set-env [name, value] { load-env { $name: $value } }
def --env unset-env [name] { hide-env $name }

let carapace_completer = {|place|
  load-env {
    CARAPACE_SHELL_BUILTINS: (help commands | where category != "" | get name | each { split row " " | first } | uniq | str join "\n")
    CARAPACE_SHELL_FUNCTIONS: (help commands | where category == "" | get name | each { split row " " | first } | uniq | str join "\n")
  }

  let spans = if ($place | describe) == "list<string>" {
    # Nu < 0.116 passes positional spans, regardless of the parameter name.
    let expanded_alias = (scope aliases | where name == $place.0 | $in.0?.expansion?)
    if $expanded_alias != null {
      $place | skip 1 | prepend ($expanded_alias | split row " " | take 1)
    } else {
      $place
    }
  } else {
    # Nu 0.116+ supplies a place record with aliases already expanded.
    $place.command
  }

  carapace $spans.0 nushell ...$spans
  | from json
}

mut current = (($env | default {} config).config | default {} completions)
$current.completions = ($current.completions | default {} external)
$current.completions.external = (
  $current.completions.external
  | default true enable
  # Backwards compatible workaround for default, see nushell #15654.
  | upsert completer { if $in == null { $carapace_completer } else { $in } }
)

$env.config = $current
