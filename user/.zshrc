#######
# shell
#######
  
  # zplug
    source $(brew --prefix zplug)/init.zsh

  # brew completions 
    FPATH=$(brew --prefix)/share/zsh/site-functions:${FPATH}
  
  # oh-my-zsh
    ZSH_THEME="kolo"
    plugins=(git)
    source ${HOME}/.oh-my-zsh/oh-my-zsh.sh

###########
# languages
###########

  # node via fnm
    eval "$(fnm env --use-on-cd)"
  
  # npm global packages via bun
    PATH="$PATH:$HOME/.bun/bin"

  # zig via zvm
    PATH="$PATH:$HOME/.zvm/bin"
    PATH="$PATH:$HOME/.zvm/self"

  # haskell
    PATH="$HOME/.ghcup/bin:$PATH"

##############
# applications
##############

  PATH="$PATH:/usr/local/bin"

  # postgresql
    PATH="$PATH:$(brew --prefix postgresql@16)/bin"

  # console-ninja
    PATH="${HOME}/.console-ninja/.bin:$PATH"

  # llvm
    PATH="$PATH:$(brew --prefix llvm@15)/bin"
    LDFLAGS="$LDFLAGS -L $(brew --prefix llvm@15)/lib"
    CPPFLAGS="$CPPFLAGS -I $(brew --prefix llvm@15)/include"

  # build your own internet
    PATH=$PATH:${HOME}/dojo/byoi/bin
