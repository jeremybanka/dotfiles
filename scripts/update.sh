#!/bin/zsh

source $HOME/.zshrc

set -eo pipefail

git pull

bun install # repo dependencies
bun scripts/npm-i.ts # system global dependencies

omz update

brew update
brew upgrade
