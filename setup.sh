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

ls -l "$HOME/.bun/install"
rm -rf "$HOME/.bun/install/global"
echo "Removing old global bun folder"
ln -sf "$VIRTUAL_HOME"/.bun/install/global "$HOME/.bun/install/global"
echo "Symlinked new global bun folder"
ls -l "$HOME/.bun/install"

echo "All dotfiles and configurations have been symlinked."
