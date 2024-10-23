# shell ########################################################################

  # zplug
    source $(brew --prefix zplug)/init.zsh

  # homebrew settings 
    FPATH=$FPATH:$(brew --prefix)/share/zsh/site-functions
    export HOMEBREW_EDITOR="codium"
  
  # oh-my-zsh
    ZSH_THEME="kolo"
    plugins=(git)
    source ${HOME}/.oh-my-zsh/oh-my-zsh.sh

# applications #################################################################

  # system
    PATH="$PATH:/usr/local/bin"
  
  # postgresql
    PATH="$PATH:$(brew --prefix postgresql@17)/bin"

  # lms (LM Studio CLI)
    PATH="$PATH:$HOME/.cache/lm-studio/bin"

# languages ####################################################################

  # node <- schniz/fnm 
    eval "$(fnm env --use-on-cd)"
  
  # global node_modules <- bun
    PATH="$PATH:$HOME/.bun/bin"

  # zig <- hendriknielaender/zvm
    PATH="$PATH:$HOME/.zvm/bin:$HOME/.zvm/self"

  # opam <- ocaml/opam
     [[ ! -r "$HOME/.opam/opam-init/init.zsh" ]] \
     || source "$HOME/.opam/opam-init/init.zsh" > /dev/null 2> /dev/null

  # haskell <- ghcup
    PATH="$PATH:$HOME/.ghcup/bin"

# projects #####################################################################

  # build your own internet
    [[ -d "$HOME/dojo/byoi/bin" ]] && PATH="$PATH:$HOME/dojo/byoi/bin"

# deal with the intractable issue of my option-key being stuck down ############

  if [[ "$(scutil --get ComputerName)" == "Eris" ]]; then
    hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E2,"HIDKeyboardModifierMappingDst":0x700000000}]}'
  fi
