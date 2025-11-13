# shell ########################################################################

  # zplug
    source $(brew --prefix zplug)/init.zsh

  # homebrew settings
    FPATH=$FPATH:$(brew --prefix)/share/zsh/site-functions
    export HOMEBREW_EDITOR="codium"

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
    setopt prompt_subst
    PROMPT=$'%B%F{magenta}%c%F{green}${vcs_info_msg_0_}%B%F{magenta}\n%B%F{magenta}└▶ %{$reset_color%}'
    autoload -U add-zsh-hook
    add-zsh-hook precmd  theme_precmd

# applications #################################################################

  # system
    PATH="$PATH:/usr/local/bin"
    PATH="$PATH:/$HOME/.local/bin"

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

  # * <- nix
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

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

# projects #####################################################################

  # build your own internet
    [[ -d "$HOME/dojo/byoi/bin" ]] && PATH="$PATH:$HOME/dojo/byoi/bin"

  # bun-debug
    PATH="$PATH:$HOME/dojo/oss/bun/build/debug"

# deal with the intractable issue of my option-key being stuck down ############

  if [[ "$(scutil --get ComputerName)" == "Eris" ]]; then
    hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E2,"HIDKeyboardModifierMappingDst":0x700000000}]}'
  fi
