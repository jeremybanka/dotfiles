#!/usr/bin/env nu

def main [instance_name?: string] {
  let lima_dir = ("~/.lima" | path expand)
  let instances = if ($instance_name | is-not-empty) {
    [$instance_name]
  } else {
    ls $lima_dir
    | where type == dir
    | where { |entry| (($entry.name | path join "lima.yaml") | path exists) }
    | get name
    | path basename
    | sort
  }

  if ($instances | is-empty) {
    error make { msg: $"No Lima instances found in ($lima_dir)" }
  }

  for instance in $instances {
    show-instance-port-forwards $lima_dir $instance
  }
}

def show-instance-port-forwards [lima_dir: string, instance: string] {
  let config_path = ($lima_dir | path join $instance "lima.yaml")

  if not ($config_path | path exists) {
    print $"($instance): missing config at ($config_path)"
    return
  }

  let config = (open --raw $config_path | from yaml)
  let port_forwards = ($config | get -o portForwards | default [])

  print $"($instance):"

  if ($port_forwards | is-empty) {
    print "  no port forwards configured"
    return
  }

  $port_forwards
  | each { |forward|
      let guest = ($forward | get -o guestPort | default "?")
      let host = ($forward | get -o hostPort | default "auto")
      let guest_ip = ($forward | get -o guestIP | default "")
      let host_ip = ($forward | get -o hostIP | default "")
      let guest_label = if ($guest_ip | is-empty) { $guest } else { $"($guest_ip):($guest)" }
      let host_label = if ($host | describe) == "int" {
        let scheme = if $host == 443 { "https" } else { "http" }
        $"($scheme)://localhost:($host)/"
      } else if ($host_ip | is-empty) {
        $host
      } else {
        $"($host_ip):($host)"
      }
      print $"  ($guest_label) -> ($host_label)"
    }
}
