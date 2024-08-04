#######
# shell
#######
  
  # zplug
    export ZPLUG_HOME=$(brew --prefix)/opt/zplug
    source $ZPLUG_HOME/init.zsh

  # brew completions 
    FPATH=$(brew --prefix)/share/zsh/site-functions:${FPATH}
  
  # ni/nr
    FPATH="$FPATH:$HOME/dotfiles/apps/ni"
  
  # oh-my-zsh
  ZSH_THEME="kolo"
    plugins=(git)
    source ${HOME}/.oh-my-zsh/oh-my-zsh.sh

###########
# languages
###########

  # node via fnm
    eval "$(fnm env --use-on-cd)"
  
  # bun
    export PATH="$HOME/.bun/bin:$PATH"

  # zig
    export PATH="$HOME/.zvm/bin:$PATH"
    export PATH="$HOME/.zvm/self:$PATH"

  # haskell
    export PATH="$HOME/.ghcup/bin:$PATH"

##############
# applications
##############

  export PATH="/usr/local/bin:$PATH"

  # postgresql
    export PATH="$(brew --prefix postgresql@16)/bin:$PATH"

  # console-ninja
    PATH="${HOME}/.console-ninja/.bin:$PATH"

  # llvm
    export PATH="$PATH:$(brew --prefix llvm@15)/bin"
    export LDFLAGS="$LDFLAGS -L$(brew --prefix llvm@15)/lib"
    export CPPFLAGS="$CPPFLAGS -I$(brew --prefix llvm@15)/include"

  # build your own internet
    export PATH=$PATH:${HOME}/dojo/byoi/bin
