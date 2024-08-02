#######
# shell
#######

  # brew
    HOMEBREW_ROOT=$(brew --prefix)
  
  # zplug
    export ZPLUG_HOME=$HOMEBREW_ROOT/opt/zplug
    source $ZPLUG_HOME/init.zsh

  # brew completions 
    FPATH=$HOMEBREW_ROOT/share/zsh/site-functions:${FPATH}
  
  # oh-my-zsh
    export OMZ_ROOT="${HOME}/.oh-my-zsh"
    ZSH_THEME="kolo"
    plugins=(git)
    source $OMZ_ROOT/oh-my-zsh.sh

###########
# languages
###########

  # node via fnm
    eval "$(fnm env --use-on-cd)"

  # bun
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"

  # zig
    export ZVM_INSTALL="$HOME/.zvm/self"
    export PATH="$PATH:$HOME/.zvm/bin"
    export PATH="$PATH:$ZVM_INSTALL/"

  # haskell
    export PATH="$HOME/.ghcup/bin:$PATH"

##############
# applications
##############

  export PATH="/usr/local/bin:$PATH"

  # postgresql
    export PATH="$HOMEBREW_ROOT/opt/postgresql@16/bin:$PATH"

  # console-ninja
    PATH="${HOME}/.console-ninja/.bin:$PATH"

  # llvm
    export PATH="$PATH:$(brew --prefix llvm@15)/bin"
    export LDFLAGS="$LDFLAGS -L$(brew --prefix llvm@15)/lib"
    export CPPFLAGS="$CPPFLAGS -I$(brew --prefix llvm@15)/include"

  # build your own internet
    export PATH=$PATH:${HOME}/dojo/byoi/bin
