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

source $HOME/.zshrc

# if there's no global bun folder, create one
if [ ! -d "$HOME/.bun/install/global" ]; then
    echo "Bun hasn't been set up yet, installing cowsay in order to create ~/.bun/install/global"
    bun i -g cowsay
    cowsay "Job's done! Now we'll remove the global folder and link it out from the repo."
    rm -rf "$HOME/.bun/install/global"
    ln -sf "$VIRTUAL_HOME"/.bun/install/global "$HOME/.bun/install/global"
    cowsay "Symlinked new global bun folder"
fi

echo "All dotfiles and configurations have been symlinked."
