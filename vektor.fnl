;imports
; NOTE dotfiles lib import [module] for now

;system configuration
; NOTE example sys configuration

; module declaration
; NOTE example module declaration

; system font | (font "ttf-jetbrains-mono-nerd"), this both downloads the font and sets it as main font
(font "Jetbrains")

; like stow, binding the dotfiles once the system is completely installed
(module :zsh
  { :plugins ["jq" "rg"]
    :shellCmd "nconfig" ; FIX only niri is supported
    :link { "niri" ".config/niri" }})

(module :neovim ; package name, only works if the package is already declared
 { :packages ["jq" "rg"]
    :shellCmd "vconfig" ; FIX only works for zsh for now
    :link { "nvim" ".config/nvim" }})

(module :niri
  { :packages ["nautilus"]
    :shellCmd "nconfig" ; FIX only niri is supported
    :link { "niri" ".config/niri" }})
