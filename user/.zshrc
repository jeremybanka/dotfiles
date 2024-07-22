#################
# package manager
#################

  # brew
    if [[ $(uname -m) == 'arm64' ]]; then
        echo "arm64"
        HOMEBREW_ROOT=/opt/homebrew/opt
    else
        HOMEBREW_ROOT=/usr/local/opt
    fi

#######
# shell
#######

  # zsh
    export ZSH="${HOME}/.oh-my-zsh"
    ZSH_THEME="kolo"
    plugins=(git)
    source $ZSH/oh-my-zsh.sh

  # zplug
    export ZPLUG_HOME=$HOMEBREW_ROOT/zplug
    source $ZPLUG_HOME/init.zsh

###########
# languages
###########

  # node
    # pnpm
      export PNPM_HOME="${HOME}/Library/pnpm"
      case ":$PATH:" in
        *":$PNPM_HOME:"*) ;;
        *) export PATH="$PNPM_HOME:$PATH" ;;
      esac
    # fnm
      eval "$(fnm env --use-on-cd)"

  # bun (and zig)
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    export PATH="~/.local/bin/lvim/:$PATH"
    # completions
      [ -s "${HOME}/.bun/_bun" ] && source "${HOME}/.bun/_bun"

  # zig
    export ZVM_INSTALL="$HOME/.zvm/self"
    export PATH="$PATH:$HOME/.zvm/bin"
    export PATH="$PATH:$ZVM_INSTALL/"

  # haskell
    [ -f "${HOME}/.ghcup/env" ] && source "${HOME}/.ghcup/env"

##############
# applications
##############

  export PATH="/usr/local/bin:$PATH"

  # postgresql
    export PATH="$HOMEBREW_ROOT/postgresql@16/bin:$PATH"

  # console-ninja
    PATH="${HOME}/.console-ninja/.bin:$PATH"

  # llvm
    export PATH="$PATH:$(brew --prefix llvm@15)/bin"
    export LDFLAGS="$LDFLAGS -L$(brew --prefix llvm@15)/lib"
    export CPPFLAGS="$CPPFLAGS -I$(brew --prefix llvm@15)/include"

  # build your own internet
    export PATH=$PATH:${HOME}/dojo/byoi/bin
