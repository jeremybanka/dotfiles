# shell ########################################################################

  # zplug
    source $(brew --prefix zplug)/init.zsh

  # homebrew settings
    FPATH=$FPATH:$(brew --prefix)/share/zsh/site-functions
    export HOMEBREW_EDITOR="zed"

  # oh-my-zsh
    plugins=(git)
    source ${HOME}/.oh-my-zsh/oh-my-zsh.sh
    autoload -Uz vcs_info

    zstyle ':vcs_info:*' stagedstr '%F{green}●'
    zstyle ':vcs_info:*' unstagedstr '%F{yellow}●'
    zstyle ':vcs_info:*' check-for-changes true
    zstyle ':vcs_info:svn:*' branchformat '%b'
    zstyle ':vcs_info:svn:*' formats ' [%b%F{1}:%F{11}%i%c%u%B%F{green}]'
    zstyle ':vcs_info:*' enable git svn

    theme_precmd () {
      if [[ -z $(git ls-files --other --exclude-standard 2> /dev/null) ]]; then
        zstyle ':vcs_info:git:*' formats ' [%b%c%u%B%F{green}]'
      else
        zstyle ':vcs_info:git:*' formats ' [%b%c%u%B%F{red}●%F{green}]'
      fi

      vcs_info
    }

    conda_env() {
      if [[ -n $CONDA_DEFAULT_ENV ]]; then
        if [[ $CONDA_DEFAULT_ENV != "base" ]]; then
          echo "%F{green}%B$CONDA_DEFAULT_ENV:"
        fi
      fi
    }

    setopt prompt_subst
    PROMPT='$(conda_env)%B%F{magenta}%c%F{green}${vcs_info_msg_0_}%B%F{magenta}
%B%F{magenta}└▶ %{$reset_color%}'

    autoload -U add-zsh-hook
    add-zsh-hook precmd  theme_precmd

# applications #################################################################

  # system
    PATH="$PATH:/usr/local/bin"
    PATH="$PATH:/$HOME/.local/bin"

  # zed
    alias z="zed"

  # vscodium
    alias c="open $1 -a \"VSCodium\""

  # postgresql
    PATH="$PATH:$(brew --prefix postgresql@18)/bin"

  # clang
    PATH="$PATH:$(brew --prefix llvm@18)/bin"

  # lms (LM Studio CLI)
    PATH="$PATH:$HOME/.cache/lm-studio/bin"

  # colima
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

  # google cloud sdk
    PATH="$PATH:$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin"
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# languages ####################################################################

  # * <- mise
    eval "$(mise activate zsh)"

  # global node_modules <- bun
    PATH="$PATH:$HOME/.bun/bin"

  # zig <- tristanisham/zvm
    PATH="$PATH:$HOME/.zvm/bin:$HOME/.zvm/self"

  # global go packages
    PATH="$PATH:$HOME/go/bin"

  # opam <- ocaml/opam
     [[ ! -r "$HOME/.opam/opam-init/init.zsh" ]] \
     || source "$HOME/.opam/opam-init/init.zsh" > /dev/null 2> /dev/null

  # haskell <- ghcup
    PATH="$PATH:$HOME/.ghcup/bin"

  # python <- conda + mamba
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

    conda config --set changeps1 False # This is OMZ's job, not conda's

    function conda_auto_env() {
      if [ -f "environment.yml" ]; then
          env_name=$(grep -m 1 'name:' environment.yml | awk '{print $2}')

          if [[ "$CONDA_DEFAULT_ENV" != "$env_name" ]]; then
              echo "Activating Conda environment \e[32m$env_name\e[0m"
              mamba activate "$env_name" || echo "Environment '$env_name' not found. Create it with 'mamba env create -f environment.yml'."
              export PY_ENV_DIR="$(pwd)"
          fi
      elif [[ $(pwd) != "$PY_ENV_DIR"* ]]; then
          echo "Deactivating Conda environment \e[32m$CONDA_DEFAULT_ENV\e[0m"
          mamba deactivate
          unset PY_ENV_DIR
      fi
    }

    autoload -U add-zsh-hook
    add-zsh-hook chpwd conda_auto_env
    conda_auto_env

# projects #####################################################################

  # build your own internet
    [[ -d "$HOME/dojo/byoi/bin" ]] && PATH="$PATH:$HOME/dojo/byoi/bin"

  # bun-debug
    PATH="$PATH:$HOME/dojo/oss/bun/build/debug"

# deal with the intractable issue of my option-key being stuck down ############

  if [[ "$(scutil --get ComputerName)" == "Eris" ]]; then
    hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E2,"HIDKeyboardModifierMappingDst":0x700000000}]}'
  fi
