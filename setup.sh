#!/bin/bash

VIRTUAL_HOME=${VIRTUAL_HOME:-$HOME/dotfiles/home}

for item in "$VIRTUAL_HOME"/* "$VIRTUAL_HOME"/.[^.]*; do
	if [ -e "$item" ]; then
		target="$HOME/$(basename "$item")"

		if [ -d "$target" ]; then
			echo "Skipping directory $item to avoid recursion."
			continue
		fi

		ln -sf "$item" "$target"
		echo "Symlinked $item to $target"
	fi
done

ln -sf "$VIRTUAL_HOME"/.bun/install/global "$HOME/.bun/install/global"

echo "All dotfiles and configurations have been symlinked."
