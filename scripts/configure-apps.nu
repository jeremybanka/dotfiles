#!/usr/bin/env nu

const repo_root = (path self ..)
const app_config_dir = ($repo_root | path join "apps")
const shared_editor_settings_source_path = ($app_config_dir | path join "VSCodium" "settings.json")
const shared_editor_keybindings_source_path = ($app_config_dir | path join "VSCodium" "keybindings.json")

def main [] {
  configure-vs-code
  configure-vscodium
  configure-cursor
  configure-illustrator
  configure-indesign
}

def configure-vs-code [] {
  configure-editor-settings "VS Code" "Code"
}

def configure-vscodium [] {
  configure-editor-settings "VSCodium" "VSCodium"
}

def configure-cursor [] {
  configure-editor-settings "Cursor" "Cursor"
}

def configure-editor-settings [app_name: string, application_support_dir_name: string] {
  let target_dir = ([$env.HOME "Library" "Application Support" $application_support_dir_name "User"] | path join)
  let configs = [
    {
      source_path: $shared_editor_settings_source_path
      target_path: ($target_dir | path join "settings.json")
    }
    {
      source_path: $shared_editor_keybindings_source_path
      target_path: ($target_dir | path join "keybindings.json")
    }
  ]

  print $"Configuring ($app_name) { targetDir: \"($target_dir)\" }"

  try {
    if not ($target_dir | path exists) {
      print $"Creating target directory: ($target_dir)"
      mkdir $target_dir
    }

    for config in $configs {
      let source_path = $config.source_path
      let target_path = $config.target_path

      if not ($source_path | path exists) {
        error make { msg: $"Source file does not exist: ($source_path)" }
      }

      print $"Configuring file { sourcePath: \"($source_path)\", targetPath: \"($target_path)\" }"

      if ($target_path | path exists --no-symlink) {
        if (($target_path | path type) == "symlink") {
          print $"Symlink already exists: ($target_path)"
          continue
        }

        print $"Removing existing file: ($target_path)"
        rm --recursive --force $target_path
      } else if (($target_path | path type) == "symlink") {
        print $"Symlink already exists: ($target_path)"
        continue
      }

      ^ln -s $source_path $target_path
      print $"Symlink created: ($source_path) -> ($target_path)"
    }
  } catch {|err|
    print --stderr $err.msg
  }
}

def configure-illustrator [] {
  let source_workspaces_dir = ($app_config_dir | path join "Illustrator" "Workspaces")
  let illustrator_prefs_dir = ([$env.HOME "Library" "Preferences"] | path join)

  if not ($illustrator_prefs_dir | path exists) {
    print "Skipping Illustrator: no Adobe preferences directory found."
    return
  }

  let matching_dirs = (
    ls $illustrator_prefs_dir
    | where type == "dir"
    | where {|row| (($row.name | path basename) | parse --regex '^Adobe Illustrator (?P<version>\d+) Settings$' | is-not-empty) }
  )

  if ($matching_dirs | is-empty) {
    print "Skipping Illustrator: no Adobe Illustrator settings directories found."
    return
  }

  let highest_version_dir = (
    find-highest-version-dir
      $illustrator_prefs_dir
      '^Adobe Illustrator (?P<version>\d+) Settings$'
      "No Adobe Illustrator settings directories found."
  )
  let target_workspaces_dir = ($highest_version_dir | path join "en_US" "Workspaces")

  configure-workspaces "Illustrator" $source_workspaces_dir $target_workspaces_dir
}

def configure-indesign [] {
  let source_workspaces_dir = ($app_config_dir | path join "InDesign" "Workspaces")
  let indesign_prefs_dir = ([$env.HOME "Library" "Preferences" "Adobe InDesign"] | path join)

  if not ($indesign_prefs_dir | path exists) {
    print "Skipping InDesign: no Adobe InDesign preferences directory found."
    return
  }

  let matching_dirs = (
    ls $indesign_prefs_dir
    | where type == "dir"
    | where {|row| (($row.name | path basename) | parse --regex '^Version (?P<version>\d+)\.0$' | is-not-empty) }
  )

  if ($matching_dirs | is-empty) {
    print "Skipping InDesign: no Adobe InDesign settings directories found."
    return
  }

  let highest_version_dir = (
    find-highest-version-dir
      $indesign_prefs_dir
      '^Version (?P<version>\d+)\.0$'
      "No Adobe InDesign settings directories found."
  )
  let target_workspaces_dir = ($highest_version_dir | path join "en_US" "Workspaces")

  configure-workspaces "InDesign" $source_workspaces_dir $target_workspaces_dir
}

def find-highest-version-dir [parent_dir: string, version_pattern: string, missing_error: string] {
  let matching_dirs = (
    ls $parent_dir
    | where type == "dir"
    | each {|row|
        let basename = ($row.name | path basename)
        let parsed = ($basename | parse --regex $version_pattern)

        if ($parsed | is-empty) {
          null
        } else {
          let entry = ($parsed | first)
          {
            name: $row.name
            version: ($entry.version | into int)
          }
        }
      }
    | compact
  )

  if ($matching_dirs | is-empty) {
    error make { msg: $missing_error }
  }

  $matching_dirs
  | sort-by version --reverse
  | first
  | get name
}

def configure-workspaces [app_name: string, source_workspaces_dir: string, target_workspaces_dir: string] {
  print $"Configuring ($app_name) { appConfigDir: \"($app_config_dir)\", sourceWorkspacesDir: \"($source_workspaces_dir)\", targetWorkspacesDir: \"($target_workspaces_dir)\" }"

  try {
    if not ($source_workspaces_dir | path exists) {
      error make { msg: $"Source workspaces directory does not exist: ($source_workspaces_dir)" }
    }

    if not ($target_workspaces_dir | path exists) {
      mkdir $target_workspaces_dir
    }

    let source_workspaces = (
      ls $source_workspaces_dir
      | get name
      | each {|name| $name | path basename }
    )

    for workspace in $source_workspaces {
      let source_workspace_path = ($source_workspaces_dir | path join $workspace)
      let target_workspace_path = ($target_workspaces_dir | path join $workspace)
      let target_type = ($target_workspace_path | path type)

      if $target_type == "symlink" {
        print $"Symlink already exists: ($target_workspace_path)"
        continue
      }

      if ($target_workspace_path | path exists --no-symlink) {
        print $"Removing existing file: ($target_workspace_path)"
        rm --recursive --force $target_workspace_path
      }

      ^ln -s $source_workspace_path $target_workspace_path
      print $"Symlink created: ($source_workspace_path) -> ($target_workspace_path)"
    }

    let target_workspaces = (
      ls $target_workspaces_dir
      | get name
      | each {|name| $name | path basename }
    )

    # Pull unmanaged existing workspaces into the repo, then link them back out.
    for workspace in $target_workspaces {
      if ($source_workspaces | any {|source_workspace| $source_workspace == $workspace }) {
        continue
      }

      let source_workspace_path = ($source_workspaces_dir | path join $workspace)
      let target_workspace_path = ($target_workspaces_dir | path join $workspace)
      let target_type = ($target_workspace_path | path type)

      if $target_type == "symlink" {
        continue
      }

      print $"Moving existing workspace to source: ($target_workspace_path) -> ($source_workspace_path)"
      mv $target_workspace_path $source_workspace_path
      ^ln -s $source_workspace_path $target_workspace_path
      print $"Symlink created: ($source_workspace_path) -> ($target_workspace_path)"
    }
  } catch {|err|
    print --stderr $err.msg
  }
}
