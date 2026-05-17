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

LIBEXEC_SOURCE="$VIRTUAL_HOME/.local/libexec"
LIBEXEC_TARGET="$HOME/.local/libexec"
LOCAL_BIN_TARGET="$HOME/.local/bin"
LAUNCH_AGENTS_TARGET="$HOME/Library/LaunchAgents"

if [ -d "$LIBEXEC_SOURCE" ]; then
	mkdir -p "$LIBEXEC_TARGET"
	mkdir -p "$LOCAL_BIN_TARGET"
	mkdir -p "$LAUNCH_AGENTS_TARGET"

	for bundle in "$LIBEXEC_SOURCE"/*; do
		if [ -d "$bundle" ]; then
			target="$LIBEXEC_TARGET/$(basename "$bundle")"

			ln -sfn "$bundle" "$target"
			echo "Symlinked libexec bundle $bundle to $target"
		fi
	done

	for agent_source in "$LIBEXEC_TARGET"/*/*-agent.swift; do
		if [ -e "$agent_source" ]; then
			agent_name="$(basename "$agent_source" .swift)"
			agent_binary="$LOCAL_BIN_TARGET/$agent_name"
			swiftc "$agent_source" -o "$agent_binary"
			target="$("$agent_binary" install-launch-agent)"
			label="$(basename "$target" .plist)"

			echo "Generated LaunchAgent $target"

			launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
			launchctl bootstrap "gui/$(id -u)" "$target"
			launchctl enable "gui/$(id -u)/$label"
			launchctl kickstart -k "gui/$(id -u)/$label"
			echo "Loaded LaunchAgent $label"
		fi
	done
fi

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
