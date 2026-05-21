#!/usr/bin/env nu

const SHA_PATTERN = '^[0-9a-f]{40}$'
const USES_PATTERN = '^(?<prefix>\s*(?:-\s+)?uses:\s+)(?<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@(?<ref>[^\s#]+)(?:\s+#\s*(?<comment>[^\r\n]+))?\s*$'
const MISE_VERSION_PATTERN = '^(?<prefix>\s*version:\s+)(?<version>\d+\.\d+\.\d+)\s*$'

def main [--dry-run] {
  let workflow_files = (list-workflow-files)
  let inventory = (collect-workflow-inventory $workflow_files)
  let workflow_uses = $inventory.workflow_uses
  let mise_version_uses = $inventory.mise_version_uses

  if (($workflow_uses | is-empty) and ($mise_version_uses | is-empty)) {
    print 'No external workflow dependencies found under .github'
    return
  }

  let workflow_groups = (group-workflow-uses $workflow_uses)
  let workflow_updates = (resolve-updates $workflow_groups)
  let mise_groups = (group-mise-version-uses $mise_version_uses)
  let mise_updates = (resolve-mise-updates $mise_groups)

  $workflow_updates | each { |update|
    if $update.has_update {
      let current_ref_label = (color-cyan ('(' + $update.current_short_ref + ')'))
      let target_ref_label = (color-cyan ('(' + (short-sha $update.target_ref) + ')'))
      print (
        $"(color-white $update.dep_name) (color-green $update.current_version) "
        + $"($current_ref_label) "
        + $"(color-cyan '->') "
        + $"(color-green $update.target_version) "
        + $"($target_ref_label) ✨"
      )
    } else {
      let current_ref_label = (color-cyan ('(' + $update.current_short_ref + ')'))
      print (
        $"(color-white $update.dep_name) (color-green $update.current_version) "
        + $"($current_ref_label)"
      )
    }
  }

  $mise_updates | each { |update|
    if $update.has_update {
      print (
        $"(color-white $update.dep_name) (color-green $update.current_version) "
        + $"(color-cyan '->') "
        + $"(color-green $update.target_version) ✨"
      )
    } else {
      print $"(color-white $update.dep_name) (color-green $update.current_version)"
    }
  }

  if $dry_run {
    print 'Dry run: no files updated'
    return
  }

  let workflow_changes = (
    $workflow_uses
    | each { |workflow_use|
        let update = (
          $workflow_updates
          | where group_key == (group-key $workflow_use.action_name $workflow_use.current_version)
          | first
        )

        if (not $update.has_update) {
          null
        } else {
          {
            file_path: $workflow_use.file_path
            line_index: $workflow_use.line_index
            replacement: $"($workflow_use.prefix)($workflow_use.action_name)@($update.target_ref) # (with-version-prefix $update.target_version)"
          }
        }
      }
    | compact
  )

  let mise_changes = (
    $mise_version_uses
    | each { |mise_use|
        let update = (
          $mise_updates
          | where current_version == $mise_use.current_version
          | first
        )

        if (not $update.has_update) {
          null
        } else {
          {
            file_path: $mise_use.file_path
            line_index: $mise_use.line_index
            replacement: $"($mise_use.prefix)($update.target_version)"
          }
        }
      }
    | compact
  )

  let file_paths = (
    ($workflow_changes | get file_path | default [])
    | append ($mise_changes | get file_path | default [])
    | uniq
    | sort
  )

  $file_paths | each { |file_path|
    let file_text = (open --raw $file_path)
    let had_trailing_newline = ($file_text | str ends-with "\n")
    let file_lines = ($file_text | split row "\n" | each {|line| $line | str replace --regex '\r$' '' })
    let updated_lines = (
      $file_lines
      | enumerate
      | each { |line|
          let workflow_change = (
            $workflow_changes
            | where file_path == $file_path and line_index == $line.index
            | get replacement
            | get -o 0
            | default null
          )
          let mise_change = (
            $mise_changes
            | where file_path == $file_path and line_index == $line.index
            | get replacement
            | get -o 0
            | default null
          )

          if ($workflow_change | is-not-empty) {
            $workflow_change
          } else if ($mise_change | is-not-empty) {
            $mise_change
          } else {
            $line.item
          }
        }
    )

    let updated_text = ($updated_lines | str join "\n")
    if $had_trailing_newline {
      ($updated_text + "\n") | save --force $file_path
    } else {
      $updated_text | save --force $file_path
    }
  }

  let file_count = ($file_paths | length)
  print $"Updated ($file_count) files"
}

def list-workflow-files [] {
  let patterns = ['.github/**/*.yml', '.github/**/*.yaml']

  $patterns
  | each { |pattern| glob $pattern }
  | flatten
  | each { |path| $path | into string }
  | uniq
  | sort
}

def collect-workflow-inventory [file_paths: list<string>] {
  let workflow_uses = (
    $file_paths
    | each { |file_path|
        let file_lines = (read-file-lines $file_path)

        $file_lines
        | enumerate
        | each { |line|
            let match = (regex-first $line.item $USES_PATTERN)
            if $match == null {
              null
            } else if ($match.action | str starts-with './') {
              null
            } else {
              let original_comment = ($match | get -o comment | default null)
              if $original_comment == null {
                null
              } else {
                {
                  file_path: $file_path
                  line_index: $line.index
                  prefix: $match.prefix
                  action_name: $match.action
                  current_ref: $match.ref
                  current_version: (normalize-version $original_comment)
                  original_comment: ($original_comment | str trim)
                }
              }
            }
          }
        | compact
      }
    | flatten
  )

  let mise_version_uses = (
    $workflow_uses
    | where action_name == 'jdx/mise-action'
    | each { |workflow_use|
        let file_lines = (read-file-lines $workflow_use.file_path)
        find-mise-version-use $workflow_use.file_path $file_lines $workflow_use.line_index
      }
    | compact
  )

  {
    workflow_uses: $workflow_uses
    mise_version_uses: $mise_version_uses
  }
}

def group-workflow-uses [workflow_uses: list<any>] {
  $workflow_uses
  | group-by {|workflow_use| group-key $workflow_use.action_name $workflow_use.current_version }
  | transpose group_key occurrences
  | each { |group|
      let first = ($group.occurrences | first)
      {
        group_key: $group.group_key
        action_name: $first.action_name
        current_version: $first.current_version
        current_ref: $first.current_ref
        occurrences: $group.occurrences
      }
    }
  | sort-by action_name
}

def group-mise-version-uses [mise_version_uses: list<any>] {
  $mise_version_uses
  | group-by current_version
  | transpose current_version occurrences
  | each { |group|
      let parsed = (parse-version $group.current_version)
      {
        dep_name: 'jdx/mise'
        current_version: $group.current_version
        occurrences: $group.occurrences
        sort_major: ($parsed | get -o major | default (-1))
        sort_minor: ($parsed | get -o minor | default (-1))
        sort_patch: ($parsed | get -o patch | default (-1))
        sort_segments: ($parsed | get -o segments | default (-1))
      }
    }
  | sort-by sort_major sort_minor sort_patch sort_segments current_version
  | reject sort_major sort_minor sort_patch sort_segments
}

def resolve-updates [groups: list<any>] {
  let repositories = ($groups | each {|group| $group.action_name } | uniq)
  let tag_cache = (
    $repositories
    | reduce --fold {} { |repository, cache|
        $cache | upsert $repository (get-repository-tags $repository)
      }
  )

  $groups
  | each { |group|
      let repository = $group.action_name
      let available_tags = ($tag_cache | get $repository)
      let target_tag = (select-latest-tag $available_tags)

      if $target_tag == null {
        {
          group_key: (group-key $group.action_name $group.current_version)
          dep_name: $group.action_name
          current_version: $group.current_version
          current_ref: $group.current_ref
          current_short_ref: (short-sha $group.current_ref)
          target_version: $group.current_version
          target_ref: $group.current_ref
          has_update: false
        }
      } else {
        let target_ref = (resolve-tag-commit $repository $target_tag)
        let target_version = (normalize-version $target_tag)
        {
          group_key: (group-key $group.action_name $group.current_version)
          dep_name: $group.action_name
          current_version: $group.current_version
          current_ref: $group.current_ref
          current_short_ref: (short-sha $group.current_ref)
          target_version: $target_version
          target_ref: $target_ref
          has_update: (($group.current_ref != $target_ref) or ($group.current_version != $target_version))
        }
      }
    }
}

def resolve-mise-updates [groups: list<any>] {
  if ($groups | is-empty) {
    return []
  }

  let available_tags = (get-repository-tags 'jdx/mise')
  let target_tag = (select-latest-tag $available_tags)

  if $target_tag == null {
    return (
      $groups
      | each { |group|
          {
            dep_name: $group.dep_name
            current_version: $group.current_version
            target_version: $group.current_version
            has_update: false
          }
        }
    )
  }

  let target_version = (normalize-version $target_tag)
  $groups
  | each { |group|
      {
        dep_name: $group.dep_name
        current_version: $group.current_version
        target_version: $target_version
        has_update: ($group.current_version != $target_version)
      }
    }
}

def get-repository-tags [repository: string] {
  let remote = $"https://github.com/($repository).git"
  let result = (^git ls-remote --tags --refs $remote | complete)

  if $result.exit_code != 0 {
    error make {
      msg: $"git ls-remote failed for ($repository)"
      label: {
        text: ($result.stderr | str trim)
      }
    }
  }

  $result.stdout
  | lines
  | each { |line|
      let columns = ($line | split row --regex '\s+')
      $columns | get -o 1 | default ''
    }
  | where {|ref| $ref != '' }
  | each {|ref| $ref | str replace 'refs/tags/' '' }
}

def select-latest-tag [tags: list<string>] {
  let stable_tags = (
    $tags
    | each { |tag|
        let parsed = (parse-version $tag)
        if $parsed == null {
          null
        } else if $parsed.prerelease != null {
          null
        } else {
          {
            tag: $tag
            major: $parsed.major
            minor: $parsed.minor
            patch: $parsed.patch
            segments: $parsed.segments
          }
        }
      }
    | compact
    | sort-by major minor patch segments --reverse
  )

  $stable_tags | get tag | get -o 0 | default null
}

def resolve-tag-commit [repository: string, tag: string] {
  let remote = $"https://github.com/($repository).git"
  let peeled_result = (^git ls-remote $remote $'refs/tags/($tag)^{}' | complete)

  if $peeled_result.exit_code != 0 {
    error make {
      msg: $"git ls-remote failed for ($repository)@($tag)"
      label: {
        text: ($peeled_result.stderr | str trim)
      }
    }
  }

  let peeled_ref = (
    $peeled_result.stdout
    | lines
    | get -o 0
    | default ''
    | split row --regex '\s+'
    | get -o 0
    | default null
  )

  if ($peeled_ref | is-not-empty) {
    return $peeled_ref
  }

  let direct_result = (^git ls-remote $remote $'refs/tags/($tag)' | complete)

  if $direct_result.exit_code != 0 {
    error make {
      msg: $"git ls-remote failed for ($repository)@($tag)"
      label: {
        text: ($direct_result.stderr | str trim)
      }
    }
  }

  let direct_ref = (
    $direct_result.stdout
    | lines
    | get -o 0
    | default ''
    | split row --regex '\s+'
    | get -o 0
    | default null
  )

  if ($direct_ref | is-empty) {
    error make { msg: $"Unable to resolve ($repository)@($tag)" }
  }

  $direct_ref
}

def parse-version [value: string] {
  let normalized = (normalize-version $value)
  let match = (
    regex-first $normalized '^(?<major>\d+)(?:\.(?<minor>\d+))?(?:\.(?<patch>\d+))?(?:-(?<prerelease>[0-9A-Za-z.-]+))?$'
  )

  if $match == null {
    null
  } else {
    {
      major: ($match.major | into int)
      minor: (($match | get -o minor | default '0') | into int)
      patch: (($match | get -o patch | default '0') | into int)
      prerelease: ($match | get -o prerelease | default null)
      segments: (
        $normalized
        | split row '-'
        | first
        | split row '.'
        | length
      )
    }
  }
}

def normalize-version [value: string] {
  $value | str trim | str replace --regex '^v' ''
}

def with-version-prefix [value: string] {
  if ($value | str starts-with 'v') {
    $value
  } else {
    $"v($value)"
  }
}

def short-sha [value: string] {
  if ((regex-first ($value | str downcase) $SHA_PATTERN) != null) {
    $value | str substring 0..8
  } else {
    $value
  }
}

def group-key [action_name: string, version: string] {
  $"($action_name)@@($version)"
}

def find-mise-version-use [file_path: string, file_lines: list<string>, action_line_index: int] {
  let action_line = ($file_lines | get -o $action_line_index | default null)
  if ($action_line | is-empty) {
    return null
  }

  let action_indent = (leading-whitespace-length $action_line)
  let trailing_lines = ($file_lines | skip ($action_line_index + 1) | enumerate)

  for line in $trailing_lines {
    let actual_index = $line.index + $action_line_index + 1
    let trimmed = ($line.item | str trim)

    if ($trimmed | is-empty) {
      continue
    }

    let current_indent = (leading-whitespace-length $line.item)
    if $current_indent < $action_indent {
      return null
    }

    let version_match = (regex-first $line.item $MISE_VERSION_PATTERN)
    if $version_match != null {
      return {
        file_path: $file_path
        line_index: $actual_index
        prefix: $version_match.prefix
        current_version: $version_match.version
      }
    }
  }

  null
}

def leading-whitespace-length [value: string] {
  let match = (regex-first $value '^(?<leading>\s*)')
  if $match == null {
    0
  } else {
    $match.leading | str length
  }
}

def read-file-lines [file_path: string] {
  open --raw $file_path
  | split row "\n"
  | each {|line| $line | str replace --regex '\r$' '' }
}

def regex-first [value: string, pattern: string] {
  let matches = ($value | parse --regex $pattern)
  if ($matches | is-empty) {
    null
  } else {
    $matches | first
  }
}

def color-white [value: string] {
  colorize (ansi white) $value
}

def color-green [value: string] {
  colorize (ansi green) $value
}

def color-cyan [value: string] {
  colorize (ansi cyan) $value
}

def colorize [color: string, value: string] {
  if ('NO_COLOR' in $env) {
    $value
  } else {
    $"($color)($value)(ansi reset)"
  }
}
