#!/bin/bash

VIRTUAL_HOME=${VIRTUAL_HOME:-$HOME/dotfiles/home}

for item in "$VIRTUAL_HOME"/* "$VIRTUAL_HOME"/.[^.]*; do
	if [ -e "$item" ]; then
		target="$HOME/$(basename "$item")"

		if [ -d "$item" ]; then
			echo "Skipping directory $item to avoid recursion."
			continue
		fi

		ln -sf "$item" "$target"
		echo "Symlinked $item to $target"
	fi
done

LAUNCH_AGENTS_SOURCE="$VIRTUAL_HOME/Library/LaunchAgents"
LAUNCH_AGENTS_TARGET="$HOME/Library/LaunchAgents"

if [ -d "$LAUNCH_AGENTS_SOURCE" ]; then
	mkdir -p "$LAUNCH_AGENTS_TARGET"

	for support_dir in "$LAUNCH_AGENTS_SOURCE"/*; do
		if [ -d "$support_dir" ]; then
			target="$LAUNCH_AGENTS_TARGET/$(basename "$support_dir")"

			ln -sfn "$support_dir" "$target"
			echo "Symlinked LaunchAgent support directory $support_dir to $target"
		fi
	done

	for plist in "$LAUNCH_AGENTS_SOURCE"/*.plist; do
		if [ -e "$plist" ]; then
			target="$LAUNCH_AGENTS_TARGET/$(basename "$plist")"
			label="$(basename "$plist" .plist)"

			ln -sf "$plist" "$target"
			echo "Symlinked LaunchAgent $plist to $target"

			launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
			launchctl bootstrap "gui/$(id -u)" "$target"
			launchctl enable "gui/$(id -u)/$label"
			launchctl kickstart -k "gui/$(id -u)/$label"
			echo "Loaded LaunchAgent $label"
		fi
	done
fi

source $HOME/.zshrc

if [ ! -d "$HOME/.bun/install/global" ]; then
    echo "Bun hasn't been set up yet, installing cowsay in order to create ~/.bun/install/global"
    bun i -g cowsay
    cowsay "Job's done! Now we'll remove the global folder and link it out from the repo."
    rm -rf "$HOME/.bun/install/global"
    echo "Removed old global bun folder."
    ln -sf "$VIRTUAL_HOME"/.bun/install/global "$HOME/.bun/install/global"
    echo "Symlinked new global bun folder from dotfiles"
fi

echo "All dotfiles and configurations have been symlinked."
