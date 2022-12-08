#!/bin/bash
BPurple='\033[1;35m'
Color_Off='\033[0m' 

set -e

# Clone dotfiles
echo -e "${BPurple}copying dotfiles 💎${Color_Off}"
clone_path="${clone_path:-"${HOME}/dotfiles"}"
# This is used to locally develop the install script.
if [ "${DEBUG}" == "1" ]; then
    cp -R "${PWD}/." "${clone_path}"
else
    git clone https://github.com/jeremybanka/dotfiles "${clone_path}"
fi
rsync -a "${clone_path}/." "${HOME}"

sh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install diff-so-fancy
brew install fzf
brew install fnm

 cat << EOF >> "${HOME}"/.bashrc
 zsh
EOF

# Done!
echo -e "${BPurple}Success! Restart terminal to get started. 🚀${Color_Off}"
exit 0