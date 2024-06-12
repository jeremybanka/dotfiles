#######
# shell
#######

  # fig
    [[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.pre.zsh"

  # zsh
    export ZSH="${HOME}/.oh-my-zsh"
    ZSH_THEME="kolo"
    plugins=(git)
    source $ZSH/oh-my-zsh.sh


  # zplug
    export ZPLUG_HOME=/opt/homebrew/opt/zplug
    source $ZPLUG_HOME/init.zsh

###########
# languages
###########

  # node
    # pnpm
      export PNPM_HOME="/Users/jem/Library/pnpm"
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
      [ -s "/Users/jem/.bun/_bun" ] && source "/Users/jem/.bun/_bun"

  # zig
    export ZVM_INSTALL="$HOME/.zvm/self"
    export PATH="$PATH:$HOME/.zvm/bin"
    export PATH="$PATH:$ZVM_INSTALL/"

  # haskell
    [ -f "/Users/jeremybanka/.ghcup/env" ] && source "/Users/jeremybanka/.ghcup/env"

##############
# applications
##############

  export PATH="/usr/local/bin:$PATH"

  # postgresql
    export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"

  # console-ninja
    PATH=~/.console-ninja/.bin:$PATH

  # llvm
    export PATH="$PATH:$(brew --prefix llvm@15)/bin"
    export LDFLAGS="$LDFLAGS -L$(brew --prefix llvm@15)/lib"
    export CPPFLAGS="$CPPFLAGS -I$(brew --prefix llvm@15)/include"

  # build your own internet
    export PATH=$PATH:~/dojo/study/build-your-own-internet/bin

  # gcloud
    if [ -f '/Users/jem/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/jem/Downloads/google-cloud-sdk/path.zsh.inc'; fi
    # completions
      if [ -f '/Users/jem/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/jem/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

######
# post
######

  # fig
    [[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.post.zsh"
