#!/bin/bash

DOTFILES_DIR=~/dotfiles/user

# Iterate through all files and directories in the dotfiles/user directory
for item in "$DOTFILES_DIR"/* "$DOTFILES_DIR"/.[^.]*; do
	if [ -e "$item" ]; then
		target="$HOME/$(basename $item)"
		ln -sf "$item" "$target"
		echo "Symlinked $item to $target"
	fi
done

echo "All dotfiles and configurations have been symlinked."
