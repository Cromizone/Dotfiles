#!/usr/bin/env sh
set -eu

dry_run=0

reset="$(tput sgr0 2>/dev/null || printf '')"
bold="$(tput bold 2>/dev/null || printf '')"
dim="$(tput dim 2>/dev/null || printf '')"

red="$(tput setaf 1 2>/dev/null || printf '')"
blue="$(tput setaf 4 2>/dev/null || printf '')"
green="$(tput setaf 2 2>/dev/null || printf '')"
yellow="$(tput setaf 3 2>/dev/null || printf '')"
magenta="$(tput setaf 5 2>/dev/null || printf '')"

if [[ -f /etc/debian_version ]]; then
  packager="apt-get"
  distro="Debian"
elif [[ -f /etc/redhat-release ]]; then
  packager="dnf"
  distro="Fedora"
elif [[ -f /etc/arch-release ]]; then
  packager="pacman"
  distro="Arch"
else
  packager=""
  distro=""
fi

if [[ $DESKTOP_SESSION ]]; then
  desktop=${DESKTOP_SESSION##*/}
elif [[ $GNOME_DESKTOP_SESSION_ID ]]; then
  desktop="gnome"
elif [[ $MATE_DESKTOP_SESSION_ID ]]; then
  desktop="mate"
else
   desktop=""
fi

#------------------------- Logging Functions -------------------------

heading() {
  local title="$1"
  local message="$2"

  printf "\n${bold}${green}[%s]${reset} ${bold}%s${reset}\n" "$title" "$message" >&1
}

error() {
  local message="$1"

  printf "${bold}${red}error:${reset} ${bold}%s${reset}\n" "$message" >&2
}

separator() {
  printf " \n"
  for i in {1..60}; do printf "-"; done
  printf " \n"
}

#-------------------------- Helper Functions -------------------------

intro() {
  printf "%s\n\n" '
                                 /$$           /$$                       /$$               /$$ /$$                    
                                | $$          |__/                      | $$              | $$| $$                    
  /$$$$$$   /$$$$$$   /$$$$$$$ /$$$$$$         /$$ /$$$$$$$   /$$$$$$$ /$$$$$$    /$$$$$$ | $$| $$  /$$$$$$   /$$$$$$ 
 /$$__  $$ /$$__  $$ /$$_____/|_  $$_/        | $$| $$__  $$ /$$_____/|_  $$_/   |____  $$| $$| $$ /$$__  $$ /$$__  $$
| $$  \ $$| $$  \ $$|  $$$$$$   | $$          | $$| $$  \ $$|  $$$$$$   | $$      /$$$$$$$| $$| $$| $$$$$$$$| $$  \__/
| $$  | $$| $$  | $$ \____  $$  | $$ /$$      | $$| $$  | $$ \____  $$  | $$ /$$ /$$__  $$| $$| $$| $$_____/| $$      
| $$$$$$$/|  $$$$$$/ /$$$$$$$/  |  $$$$/      | $$| $$  | $$ /$$$$$$$/  |  $$$$/|  $$$$$$$| $$| $$|  $$$$$$$| $$      
| $$____/  \______/ |_______/    \___/        |__/|__/  |__/|_______/    \___/   \_______/|__/|__/ \_______/|__/      
| $$                                                                                                                  
| $$                                                                                                                  
|__/                                                                                                                  '

}

extract() {
  file="$1"
  target="$2"
  expander=""

  set +e
  case "$file" in
    *.tar.xz)
      expander="tar"
      [ $dry_run -le 0 ] && sudo tar -xo -C "$target" -f "$file" > /dev/null 2>&1 
      ;;
    *.tar.gz)
      expander="tar"
      [ $dry_run -le 1 ] && sudo tar -xo -C "$target" -f "$file" > /dev/null 2>&1 
      ;;
    *.txz)
      expander="tar"
      [ $dry_run -le 1 ] && sudo tar -xo -C "$target" -f "$file" > /dev/null 2>&1 
      ;;
    *.zip)
      expander="unzip"
      [ $dry_run -le 0 ] && sudo unzip -qqo -d "$target" "$file" > /dev/null 2>&1 
      ;;
    *)
      error "unsupported archive '$file' given for expanding"
      exit 1
  esac

  if ! [[ $? -eq 0 ]] && [[ $dry_run -le 0 ]]; then
    error "failed to expand archive '$file' into '$target' using $expander"
    exit 1
  fi
  set -e
}

install_package() {
  packages="$@"
  options=""

  set +e

  case "$packager" in
    apt-get)
      options="-qq install"
      ;;
    dnf)
      options=" -yqd=2 install"
      ;;
    pacman)
      options=""
      ;;
    *) 
      error "can't find appropriate package manager"
      exit 1
  esac

  [ $dry_run -le 0 ] && sudo $packager $options $packages
  if ! [[ $? -eq 0 ]] && [[ $dry_run -le 0 ]]; then
    error "fail to install packages[$packages] using $packager"
    exit 1
  fi
  
  set -e
}

elevate() {
  if [[ $(id -u) -eq 0 ]]; then
    error "can't elevate already elevated user"
    exit 1
  fi

  if ! sudo -v > /dev/null 2>&1; then
    error "superuser privileges are required to run this script"
    exit 1
  fi
}

#--------------------------- Core Functions --------------------------

install_font() {
  name="$1"
  source="$2"
  filename=$(basename -- "$source")
  tempfile=$(mktemp -t "XXX.$filename")
  destination="$HOME/.local/share/fonts/$name"

  heading "FONT" "installing $name under $destination"

  printf " %s\n" "creating font directory at $destination"
  [ $dry_run -le 0 ] && mkdir -p $destination

  printf " %s\n" "downloading '$filename' from $source"
  [ $dry_run -le 0 ] && sudo curl -fsL "$source" > "$tempfile"

  printf " %s\n" "expanding archive '$filename' to $destination"
  extract "$tempfile" "$destination" # dry run is auto handled in this function

  printf " %s\n" "updating system font cache"
  [ $dry_run -le 0 ] && fc-cache -f 

  rm "$tempfile"
}

install_applications() {
  packages="gparted kitty timeshift grub-customizer"

  if [[ $desktop = "gnome" ]]; then
    packages="${packages} gnome-tweaks"
  else
    packages="${packages} lxappearance"
  fi

  heading "PACKAGE" "installing graphical applications ${dim}($(echo $packages | sed "s/ /, /g"))${reset}"
  install_package "$packages"
}

install_flatpaks() {
  include_development=1
  include_editor=0
  include_photo_editors=0
  include_entertainment=0

  program_names="Flatseal Warehouse"
  flatpaks="com.github.tchx84.Flatseal io.github.flattool.Warehouse"

  [ $include_development -eq 1 ] && flatpaks="$flatpaks com.vscodium.codium com.getpostman.Postman org.turbowarp.TurboWarp" && program_names="$program_names Codium Postman TurboWarp"
  [ $include_editor -eq 1 ] && flatpaks="$flatpaks org.audacityteam.Audacity org.kde.kdenlive" && program_names="$program_names Audacity Kdenlive"
  [ $include_photo_editors -eq 1 ] && flatpaks="$flatpaks org.inkscape.Inkscape org.gimp.GIMP" && program_names="$program_names Inkscape Gimp"
  [ $include_entertainment -eq 1 ] && flatpaks="$flatpaks com.spotify.Client" && program_names="$program_names Spotify"

  heading "FLATPAK" "installing flathub programs ${dim}($(echo $program_names | sed "s/ /, /g"))${reset}"

  set +e
  if [[ $(command -v "flatpak" >/dev/null) -ne 0 ]]; then
    if [[ $desktop -eq "gnome" ]]; then
      printf "%s\n" "looks like flatpak isn't installed, therefor installing flatpak with Gnome desktop backend"
      install_package "flatpak gnome-software-plugin-flatpak"
    elif [[ $desktop -eq "kde" ]]; then
      printf "%s\n" "looks like flatpak isn't installed, therefor installing flatpak with KDE desktop backend"
      install_package "flatpak plasma-discover-backend-flatpak"
    else
      printf "%s\n" "looks like flatpak isn't installed, therefor installing flatpak"
      install_package "flatpak"
    fi
  fi

  printf "%s\n" "adding flathub repository to flatpak"
  [ $dry_run -le 0 ] && flatpak remote-add -u --if-not-exists "flathub" "https://dl.flathub.org/repo/flathub.flatpakrepo"

  printf "%s\n" "starting installtion of flatpaks"
  [ $dry_run -le 0 ] && flatpak install -uy --or-update flathub "$flatpaks"

  set -e
}

configure_prompt() {
  local install_destination="/usr/local/bin"
  local configuration="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/starship/starship.toml"
  local starship="https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz"

  local filename=$(basename -- "$starship")
  local tempfile=$(mktemp -t "XXX.$filename")

  heading "PROMPT" "downloading and installing starship prompt"

  printf " %s\n" "downloading starship from $starship"
  [ $dry_run -le 0 ] && sudo curl -fsL "$starship" > "$tempfile"

  printf " %s\n" "installing starship into $install_destination/"
  extract "$tempfile" "/usr/local/bin/" #/usr/local/bin/ is used for installing user installed applications and not by any package manager or distribution

  [ $dry_run -le 0 ] && mkdir -p "$HOME/.config"
  if [[ -f "$HOME/.config/starship.toml" ]]; then
    printf " %s\n" "existing starship configuration detected, moving configuration to $HOME/.backup/starship.toml"

    [ $dry_run -le 0 ] && mkdir -p "$HOME/.backup"
    [ $dry_run -le 0 ] && mv "$HOME/.config/starship.toml" "$HOME/.backup/starship.toml"
  fi

  printf " %s\n" "writing prompt configuration into $HOME/.config/starship.toml"
  [ $dry_run -le 0 ] && curl -fsL "$configuration" > "$HOME/.config/starship.toml"

  rm "$tempfile"
}

configure_kitty() {
  local configuration="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/kitty/kitty.conf"
  local theme="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/kitty/theme.conf"

  heading "KITTY" "configuring kitty terminal emulator"

  if [[ -f "$HOME/.config/kitty/kitty.conf" ]]; then
    printf " %s\n" "existing kitty configuration detected, moving configuration to $HOME/.backup/kitty/kitty.conf"

    [ $dry_run -le 0 ] && mkdir -p "$HOME/.backup/kitty"
    [ $dry_run -le 0 ] && mv "$HOME/.config/kitty/kitty.conf" "$HOME/.backup/kitty/"
  fi

  if [[ -f "$HOME/.config/kitty/theme.conf" ]]; then
    printf " %s\n" "existing kitty theme detected, moving configuration to $HOME/.backup/kitty/kitty.conf"

    [ $dry_run -le 0 ] && mkdir -p "$HOME/.backup/kitty"
    [ $dry_run -le 0 ] && mv "$HOME/.config/kitty/theme.conf" "$HOME/.backup/kitty/"
  fi

  printf " %s\n" "writing kitty configuration to $HOME/.config/kitty/kitty.conf"
  [ $dry_run -le 0 ] && curl -fsL "$configuration" > "$HOME/.config/kitty/kitty.conf"

  set +e
  printf " %s\n" "writing theme configuration to $HOME/.config/kitty/theme.conf"
  [ $dry_run -le 0 ] && curl -fsl "$theme" > "$HOME/.config/kitty/theme.conf"
  
  set -e
}

configure_bash() {
  local bashrc="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/bash/.bashrc"

  heading "BASH" "configuring bash shell"

  if [[ -f "$HOME/.bashrc" ]]; then
    printf " %s\n" "existing bashrc file detected, moving rc file into $HOME/.backup"

    [ $dry_run -le 0 ] && mkdir -p "$HOME/.backup"
    [ $dry_run -le 0 ] && mv "$HOME/.bashrc" "$HOME/.backup"
  fi

  printf " %s\n" "writing bash configuration to $HOME/.bashrc"
  [ $dry_run -le 0 ] && curl -fsL "$bashrc" > "$HOME/.bashrc"
}

#--------------------------- Main Sequence ---------------------------
main() {
  elevate
  clear
  intro

  install_font "SourceCodePro" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/SourceCodePro.tar.xz"
  install_font "JetBrainsMono" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
  install_font "FiraCode" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz"
  install_font "Roboto" "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
  install_font "Inter" "https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip"

  separator
  heading "PACKAGE" "install basic terminal utilities ${dim}(ffmpeg, bat, eza, cava, btop)${reset}"
  case "$distro" in
    "Debian")
      install_package "eza bat cava ffmpeg btop"
      ;;
    "Fedora")
      install_package "eza bat cava ffmpeg-free btop"
      ;;
    *)
      error "unsupported distribution"
      exit 1
      ;;
  esac

  install_applications
  install_flatpaks
  configure_prompt

  separator
  configure_kitty
  configure_bash

  printf "\n"
}

main
