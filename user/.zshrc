# shell ########################################################################

  # zplug
    source $(brew --prefix zplug)/init.zsh

  # brew completions 
    FPATH=$FPATH:$(brew --prefix)/share/zsh/site-functions
  
  # oh-my-zsh
    ZSH_THEME="kolo"
    plugins=(git)
    source ${HOME}/.oh-my-zsh/oh-my-zsh.sh

# applications #################################################################

  # system
    PATH="$PATH:/usr/local/bin"

  # postgresql
    PATH="$PATH:$(brew --prefix postgresql@16)/bin"

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
