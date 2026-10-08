use core.nu *

export def path-bytes [paths: list] {
  $paths | each {|p|
    if (kind $p) == file { ls -D -l $p | first | get size | into int } else { 0 }
  } | prepend 0 | math sum
}
export def free-bytes [directory: string] {
  let row = (invoke [df -Pk $directory] | lines | last | split row --regex '\s+' | where {|v| $v != '' })
  if ($row | length) < 6 { fail 'Cannot determine free staging space' }
  ($row | get 3 | into int) * 1024
}
# Allow a second payload for a worst-case archive plus metadata headroom,
# while leaving 2 GiB for the user's running processes. This is a preflight
# estimate, not a reservation against other processes consuming free space.
export def require-space [available: int payload: int --reserve: int = 2147483648] {
  let required = ($payload * 2) + (($payload + 9) // 10) + 536870912 + $reserve
  if $available < $required { fail $'Insufficient staging space: need ($required) bytes including reserve, have ($available)' }
  {payload_bytes: $payload required_bytes: $required available_bytes: $available reserve_bytes: $reserve}
}
