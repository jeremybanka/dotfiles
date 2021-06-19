syntax on

set ttyfast

" Enable mouse use in all modes
set mouse=a
"
" " Set this to the name of your terminal that supports mouse codes.
" " Must be one of: xterm, xterm2, netterm, dec, jsbterm, pterm
set ttymouse=xterm2


set nocp
set incsearch
set hlsearch
set ruler
set showcmd
set et
set t_Co=256
set shiftwidth=2
set tabstop=2
" set bg=dark
set smartcase
" set clipboard=unnamed

hi Search ctermbg=7

" Vundle -----------------------------------------------------------

set nocompatible " be iMproved, required
filetype off " required
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

Plugin 'gmarik/Vundle.vim' " let Vundle manage Vundle, required
Plugin 'tpope/vim-fugitive'
Bundle 'ervandew/supertab'
Plugin 'suan/vim-instant-markdown'
Bundle 'tpope/vim-surround'
Bundle 'elzr/vim-json'
Bundle 'chriskempson/base16-vim'
" Track the engine.
" Snippets are separated from the engine. Add this if you want them:
Plugin 'honza/vim-snippets'
" Bundle 'Lokaltog/vim-powerline'
Bundle 'bling/vim-airline'
Bundle 'scrooloose/syntastic'
Bundle 'scrooloose/nerdtree'
Bundle 'rking/ag.vim'
Plugin 'digitaltoad/vim-jade'
Plugin 'airblade/vim-gitgutter'
Plugin 'mxw/vim-jsx'
" Plugin 'facebook/vim-flow'
Plugin 'tmhedberg/matchit'

call vundle#end()            " required
filetype plugin indent on    " required

" END VUNDLE --------------------------------------

""""""""""""""
"  Snippets  "
""""""""""""""



"""""""""""""
"  airline  "
"""""""""""""

" let g:airline_enable_branch = 1
let g:airline#extensions#branch#enabled = 1
" let g:airline_enable_syntastic = 1
let g:airline#extensions#syntastic#enabled = 1
set laststatus=2
" powerline symbols
let g:airline_left_sep = ''
let g:airline_left_alt_sep = ''
let g:airline_right_sep = ''
let g:airline_right_alt_sep = ''
" let g:airline_branch_prefix = ''
" let g:airline_symbols.branch = ''
" let g:airline_readonly_symbol = ''
" let g:airline_symbols.readonly = ''
" let g:airline_linecolumn_prefix = ''
" let g:airline_symbols.linenr = ''

"""""""""""""""""
"  colorscheme  "
"""""""""""""""""

highlight OverLength ctermbg=red ctermfg=white guibg=#592929
match OverLength /\%121v.\+/

autocmd BufNewFile,BufReadPost *.md set filetype=markdown
autocmd BufNewFile,BufReadPost *.tsx set filetype=typescript

" Strip trailing whitespace on save for some filetypes
autocmd FileType c,cpp,python,javascript,typescript,htmldjango,less,scss,css,make,json,jade
 \ autocmd BufWritePre <buffer> :%s/\s\+$//e

" remap 'page down" to the space key
nnoremap <SPACE> <PAGEDOWN>

" Instantly tweak .vimrc and apply changes
nmap <silent> ;v        :next $MYVIMRC<CR>
augroup VimReload
    autocmd! BufWritePost $MYVVIMRC nested :source $MYVVIMRC
augroup END

" Alternatively use
nnoremap <C-l> :tabnext<CR>
nnoremap <C-h> :tabprev<CR>
" nnoremap <silent> <C-n> :tabnext<CR>
" nnoremap <silent> <C-p> :tabprevious<CR>

set noai
"
""""""""""""""""""""""
"  syntastic / flow  "
""""""""""""""""""""""
let g:syntastic_aggregate_errors = 1
let frost_proj_root=$FROST_PROJECT_ROOT
if frost_proj_root != ""
    let g:syntastic_typescript_checkers = ['tsc', 'tslint']
    execute "let g:syntastic_typescript_tsc_args='--jsx react --moduleResolution node -t es6 --noEmit ".frost_proj_root."/typings/tsd.d.ts'"
endif

let g:flow#enable = 0 " doesn't seem to work.
let g:flow#errjmp = 0

set statusline+=%{SyntasticStatuslineFlag()}
"let g:syntastic_javascript_checkers=["flow"]
let g:syntastic_javascript_checkers=["eslint"]
let g:syntastic_python_checkers=["flake8"]
let eslint_rules_dir=$ESLINT_RULES_DIR
if eslint_rules_dir != ""
    execute "let g:syntastic_javascript_eslint_args=' --rulesdir ".eslint_rules_dir."'"
endif

