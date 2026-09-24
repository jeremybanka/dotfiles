use core.nu *

# Read only headers, retaining at most one chunk plus bounded PAX metadata.
# Payloads are streamed past, so repository size does not determine RAM usage.
def field [header: binary start: int length: int] {
  $header | bytes at $start..<($start + $length) | bytes split 0x[00] | first | decode utf-8
}
def octal [header: binary start: int length: int] {
  let text = (field $header $start $length | str trim)
  if $text == '' { 0 } else { $text | into int --radix 8 }
}
def pax-fields [data: binary] {
  mut rest = $data
  mut result = {}
  while ($rest | bytes length) > 0 {
    let prefix = ($rest | bytes at 0..<32 | decode utf-8 | split row ' ' | first)
    let n = ($prefix | into int)
    if $n <= ($prefix | str length) or $n > ($rest | bytes length) { fail 'Invalid PAX record length' }
    let pair = ($rest | bytes at (($prefix | str length) + 1)..<($n - 1) | decode utf-8 | split row '=' --number 2)
    if ($pair | length) != 2 { fail 'Invalid PAX record' }
    if $pair.0 not-in [path linkpath size mtime atime ctime LIBARCHIVE.creationtime uid gid uname gname] { fail $"Unsupported PAX extension: ($pair.0)" }
    $result = ($result | upsert $pair.0 $pair.1)
    $rest = ($rest | bytes at $n..)
  }
  $result
}
export def tar-index [artifact: string] {
  # Let the native tar reader validate header checksums and compressed-stream
  # integrity. Summing each header byte in Nu is prohibitively slow for large
  # dependency trees. The parser below still enforces our stricter member,
  # extension, duplicate, traversal, and end-of-archive rules.
  invoke [tar -tf $artifact] | ignore
  mut buffer = 0x[]
  mut remaining = 0
  mut extension = ''
  mut metadata = 0x[]
  mut pending = {}
  mut members = []
  mut batches = []
  mut ended = false
  # gzip errors propagate after its output stream is consumed.
  for chunk in (^gzip -dc -- $artifact | chunks 1mb) {
    $buffer = ($buffer ++ $chunk)
    loop {
      if $remaining > 0 {
        let take = ([$remaining ($buffer | bytes length)] | math min)
        if $extension != '' { $metadata = ($metadata ++ ($buffer | bytes at 0..<$take)) }
        $buffer = ($buffer | bytes at $take..)
        $remaining = $remaining - $take
        if $remaining > 0 { break }
        if $extension != '' {
          let data = ($metadata | bytes at 0..<$pending._size)
          $pending = ($pending | reject _size)
          if $extension == x { $pending = ($pending | merge (pax-fields $data)) } else if $extension == L {
            $pending = ($pending | upsert path ($data | bytes split 0x[00] | first | decode utf-8))
          } else { $pending = ($pending | upsert linkpath ($data | bytes split 0x[00] | first | decode utf-8)) }
          $metadata = 0x[]
          $extension = ''
        }
      }
      if ($buffer | bytes length) < 512 { break }
      let header = ($buffer | bytes at 0..<512)
      $buffer = ($buffer | bytes at 512..)
      if ($header | chunks 1 | all {|b| $b == 0x[00] }) { $ended = true; continue }
      if $ended { fail 'Nonzero tar data after archive end' }
      let type = (field $header 156 1)
      let size = (octal $header 124 12)
      if $size < 0 { fail 'Negative tar member size' }
      if $type in [x L K] {
        if $size > 1048576 { fail 'Oversized tar extension' }
        $extension = $type
        $pending = ($pending | upsert _size $size)
        $remaining = ((($size + 511) // 512) * 512)
        continue
      }
      if $type not-in ['' '0' '2' '5'] { fail $"Unsafe or unsupported tar member type: ($type)" }
      let prefix = (field $header 345 155)
      let rawname = if 'path' in $pending { $pending.path } else if $prefix != '' { $prefix + '/' + (field $header 0 100) } else { field $header 0 100 }
      let name = ($rawname | str trim --right --char '/')
      if not (safe-relative $name) { fail $"Unsafe or duplicate archive member: ($name)" }
      let actual_size = if 'size' in $pending { $pending.size | into int } else { $size }
      if $actual_size < 0 or ($type in ['2' '5'] and $actual_size != 0) { fail 'Invalid tar member size' }
      let link = ($pending.linkpath? | default (field $header 157 100))
      $members = ($members | append {name: $name type: (if $type == '2' { 'symlink' } else if $type == '5' { 'directory' } else { 'file' }) size: $actual_size target: $link})
      # Bound list-copy work while collecting large dependency trees.
      if ($members | length) == 1024 {
        $batches = ($batches | append [$members])
        $members = []
      }
      $pending = {}
      $remaining = ((($actual_size + 511) // 512) * 512)
    }
  }
  invoke [gzip -t -- $artifact] | ignore
  if not $ended or $remaining != 0 or ($pending | is-not-empty) { fail 'Truncated tar archive' }
  let result = ($batches | append [$members] | flatten)
  # Nothing has been extracted. Sort ALL names across ALL batches so even
  # nonadjacent duplicates are rejected before unpack/native extraction.
  let duplicates = ($result | get name | sort | uniq --repeated)
  if ($duplicates | is-not-empty) { fail $"Unsafe or duplicate archive member: ($duplicates.0)" }
  $result
}
export def unpack [artifact: string stage: string] {
  let members = (tar-index $artifact)
  let manifest_member = ($members | where name == manifest.json)
  if ($manifest_member | length) != 1 or $manifest_member.0.type != file { fail 'Missing manifest file' }
  let manifest = (invoke [tar -xOf $artifact manifest.json] | from json)
  if $manifest.format != 1 { fail 'Unsupported chat archive format' }
  mut payloads = []
  for root in $manifest.roots {
    if $root.payload !~ '^workspaces/[0-9]+$' or $root.payload in $payloads { fail 'Invalid or duplicate workspace payload' }
    if not ($root.source | str starts-with '/') or '..' in ($root.source | split row '/') { fail 'Invalid source workspace path' }
    if ($manifest.files | get $root.payload | get type) != directory { fail 'Workspace payload root must be a directory' }
    $payloads = ($payloads | append $root.payload)
  }
  let links = ($members | where type == symlink | get name)
  let link_index = if ($links | is-empty) { {} } else { $links | each {|p| {name: $p linked: true} } | transpose --header-row --ignore-titles --as-record }
  let actual_names = ($members | where {|m| $m.name not-in [manifest.json codex workspaces] } | get name | sort)
  for entry in ($manifest.files | transpose name record) {
    if not ($chat_paths | any {|p| under $entry.name ('codex/' + $p) }) and not ($payloads | any {|p| under $entry.name $p }) { fail $"Unexpected payload path: ($entry.name)" }
  }
  for m in $members {
    mut ancestor = ''
    for part in ($m.name | split row '/' | drop 1) {
      $ancestor = if $ancestor == '' { $part } else { $ancestor + '/' + $part }
      if $ancestor in $link_index { fail 'Archive member traverses a symlink' }
    }
    if $m.name in $manifest.files {
      let r = ($manifest.files | get $m.name)
      if $r.type != $m.type { fail $"Member type mismatch: ($m.name)" }
      if $m.type == file and $r.size != $m.size { fail $"Size mismatch: ($m.name)" }
      if $m.type == symlink and $r.target != $m.target { fail $"Symlink mismatch: ($m.name)" }
    } else if $m.name not-in [manifest.json codex workspaces] or ($m.name != manifest.json and $m.type != directory) { fail 'Archive contents do not match manifest' }
  }
  if ($manifest.files | columns | sort) != $actual_names { fail 'Archive contents do not match manifest' }
  mkdir $stage
  # All paths/types and link ancestors were validated before native extraction.
  invoke [tar -xzf $artifact -C $stage] | ignore
  # tar restores directory modes at the end. Make staging traversable before
  # hashing/repairing; recursive chmod does not follow encountered symlinks.
  invoke [chmod -R 'u+rwX' $stage] | ignore
  for entry in ($manifest.files | transpose name record) {
    let p = ($stage | path join $entry.name)
    let r = $entry.record
    if $r.type == file {
      if (digest $p) != $r.sha256 { fail $"Checksum mismatch: ($entry.name)" }
      chmod-mode $p $r.mode
    } else if $r.type == directory { chmod-mode $p 448 }
  }
  $manifest
}
export def snapshot [source: string target: string prefix: string] {
  mut records = {}
  let paths = ([$source] | append (walk $source))
  for p in $paths {
    let rel = if $p == $source { $prefix } else { $prefix + '/' + ($p | path relative-to $source) }
    let dest = if $p == $source { $target } else { $target | path join ($p | path relative-to $source) }
    let m = (mode $p)
    let type = (kind $p)
    let r = match $type {
      symlink => { mkdir ($dest | path dirname); let link = (invoke [readlink $p]); invoke [ln -s -- $link $dest] | ignore; {type: symlink target: $link mode: $m} }
      dir => { mkdir $dest; {type: directory mode: $m} }
      file => {
        let before = (ls -D -l $p | first | select size modified)
        copy $p $dest
        let after = (ls -D -l $p | first | select size modified)
        if $before != $after { fail $"File changed during export: ($p)" }
        {type: file mode: $m size: ($after.size | into int) sha256: (digest $dest)}
      }
      _ => { fail $"Cannot preserve special file: ($p); stop its owning process first" }
    }
    $records = ($records | insert $rel $r)
  }
  $records
}
export def inspect-archive [artifact: string] {
  temporary {|temp|
    let m = (unpack $artifact ($temp | path join stage))
    $m | select format export_id codex_version roots missing excluded_codex_entries | insert threads ($m.threads | each {|t|
      {id: $t.id title: ($t.name? | default ($t.title?)) cwd: $t.cwd? archived: (($t.archived? | default 0) == 1) updated_at: $t.updated_at?}
    })
  }
}
