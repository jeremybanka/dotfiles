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

  # colima
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

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

  # python <- conda
    __conda_setup="$("$(brew --prefix)/Caskroom/miniforge/base/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "$(brew --prefix)/Caskroom/miniforge/base/etc/profile.d/conda.sh" ]; then
            . "$(brew --prefix)/Caskroom/miniforge/base/etc/profile.d/conda.sh"
        else
            export PATH="$PATH:$(brew --prefix)/Caskroom/miniforge/base/bin"
        fi
    fi
    unset __conda_setup

    if [ -f "$(brew --prefix)/Caskroom/miniforge/base/etc/profile.d/mamba.sh" ]; then
      . "$(brew --prefix)/Caskroom/miniforge/base/etc/profile.d/mamba.sh"
    fi

  # google cloud sdk
    PATH="$PATH:$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin"
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True


# projects #####################################################################

  # build your own internet
    [[ -d "$HOME/dojo/byoi/bin" ]] && PATH="$PATH:$HOME/dojo/byoi/bin"

# deal with the intractable issue of my option-key being stuck down ############

  if [[ "$(scutil --get ComputerName)" == "Eris" ]]; then
    hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E2,"HIDKeyboardModifierMappingDst":0x700000000}]}'
  fi
