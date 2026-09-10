# User-installed binaries are available in every zsh session.
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  path=("$HOME/.local/bin" "${path[@]}")
fi
export PATH
