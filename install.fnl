(local {: module : run!} (require :lib.dotfiles))

(module :zsh
  {:packages [:zsh :zsh-autosuggestions :zsh-syntax-highlighting]
   :links {"zsh/.zshrc"  "~/.zshrc"
           "zsh/.zshenv" "~/.zshenv"}})

(module :niri
  {:packages [:niri :xdg-desktop-portal-gtk]
   :links {"niri/config.kdl" "~/.config/niri/config.kdl"}})
