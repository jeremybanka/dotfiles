#!/bin/bash

DOTFILES_DIR=~/dotfiles/user

for item in "$DOTFILES_DIR"/* "$DOTFILES_DIR"/.[^.]*; do
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

echo "All dotfiles and configurations have been symlinked."
