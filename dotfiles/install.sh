#!/usr/bin/env bash
set -eu pipefail

readonly font_directory="$HOME/.local/share/fonts"
readonly user_binaries="/usr/local/bin"

reset="$(tput sgr0 2>/dev/null || printf '')"
bold="$(tput bold 2>/dev/null || printf '')"
dim="$(tput dim 2>/dev/null || printf '')"
red="$(tput setaf 1 2>/dev/null || printf '')"
blue="$(tput setaf 4 2>/dev/null || printf '')"
green="$(tput setaf 2 2>/dev/null || printf '')"

last_title=""

#-----------Logging-----------#

log() {
  local message="$@"
  printf " %s\n" "$message"
}

separator() {
  printf " \n"
  for i in {1..60}; do printf "-"; done
  printf " \n"
}

heading() {
  local title="$1"
  local message="$2"

  if [[ ! -z "$last_title" ]] && [[ "$last_title" != "$title" ]]; then
    separator
  fi

  printf "\n${bold}${green}[%s]${reset} ${bold}%s${reset}\n" "$title" "$message"
  last_title="$title"
}

error() {
  local message="$1"
  printf "${bold}${red}error:${reset} ${bold}%s${reset}\n" "$message" >&2
}

#-----------Helpers-----------#

elevate() {
  set +e

  if [[ $(id -u) -eq 0 ]]; then
    error "can't elevate already elevated user root user"
    exit 1
  fi

  if ! sudo -v >/dev/null 2>&1; then
    error "superuser privileges are required to run this script"
    exit 10
  fi

  set -e
}

get_distribution() {
  local distribution=""

  if [[ -f "/etc/debian_version" ]]; then
    distribution="debian"
  elif [[ -f "/etc/fedora-release" ]]; then
    distribution="fedora"
  fi

  printf "%s" "$distribution"
}

fetch() {
  local url="$1"

  local status=""
  local options=""
  local fetcher=""

  set +e

  if [[ $(command -v curl) ]]; then
    fetcher="curl"
    options="--progress-bar --fail --location"
  else
    error "please install curl to fetch resources from internet"
    exit 2
  fi

  $fetcher $options "$url"
  if [[ $? -ne 0 ]]; then
    error "fail to fetch resource from ${blue}${bold}'${url}'${reset}"
    exit 10
  fi

  if [[ $(command -v tput) ]] && [[ $fetcher == "curl" ]]; then
    tput cuu 1 >&2
    tput el >&2
  fi

  set -e
}

extract() {
  local file="$1"
  local destination="$2"

  local sudo=""
  if [[ $(id -u) -ne 0 ]] && [[ ! -w "$destination" ]] || [[ ! -w "$destination/*" ]] || [[ ! -r "$file" ]]; then
   elevate
   sudo="sudo --non-interactive"
  fi

  set +e

  case "$file" in
    *.tar.xz | *.tar.gz)
      $sudo tar -xo -C "$destination" -f "$file" > /dev/null 2>&1
      ;;
    *.zip)
      $sudo unzip -qqo -d "$destination" "$file" > /dev/null 2>&1
      ;;
    *)
      error "unsupported archive format: ${bold}${green}'$file'${reset}"
      exit 1
      ;;
  esac

  if [[ $? -ne 0 ]]; then
    error "fail to extract ${bold}${green}'${file}'${reset}${bold} into ${bold}${green}'${destination}'${reset}"
    exit 10
  fi

  set -e
}

download() {
  local url="$1"
  local destination="$2"

  if [[ -d "$destination" ]]; then
    error "write destination can't be a directory"
    exit 1
  fi

  set +e

  fetch "$url" >"$destination"
  if [[ $? -ne 0 ]]; then
    error "an unexpected error occured while writing ${bold}${green}'${destination}'${reset}"
    exit 10
  fi

  set -e
}

#-----------Core Logic-----------#

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

install_font() {
  local name="$1"
  local url="$2"

  local filename="$(basename -- "$url")"
  local tempfile="$(mktemp -t "Font.XXX.$filename")"

  heading "FONT" "installing $name font under ${green}'${font_directory}'${reset}"

  log "downloading ${green}'${filename}'${reset} from ${blue}'${url}'${reset}"
  download "$url" "$tempfile"

  log "extracting ${green}'${filename}'${reset} to ${green}'${font_directory}'${reset}"
  mkdir -p "${font_directory}/${name}"
  extract "$tempfile" "${font_directory}/${name}"

  log "updating system font cache"
  fc-cache -f

  rm "$tempfile"
}

install_packages() {
  local packages="$@"

  local manager=""
  local options=""
  local command=""
  local distribution=$(get_distribution)

  case "$distribution" in
    "debian")
      manager="apt-get"
      options="--quiet --assume-yes"
      command="install"
      ;;
    "fedora")
      manager="dnf"
      options="--quiet --debuglevel=2 --assumeyes"
      command="install"
      ;;
    *)
      error "unsupported linux distribution"
      exit 1
      ;;
  esac

  sudo $manager $options $command $packages 2>/dev/null
  if [[ $? -ne 0 ]]; then
    error "fail to install these packages using ${blue}${bold}${manager}${reset}${bold}: ${packages}"
    exit 10
  fi
}

install_flatpaks() {
  local flatpaks="$@"

  local options="--assumeyes --or-update"
  local command="install"
  local remote="flathub"
  local remote_url="https://dl.flathub.org/repo/flathub.flatpakrepo"

  if [[ ! $(command -v flatpak) ]]; then
    error "flatpak isn't installed on you system or isn't in your PATH variable"
    exit 10
  fi

  log "adding flathub remote to flatpak"
  flatpak remote-add --if-not-exists "$remote" "$remote_url" 2>&1
  if [[ $? -ne 0 ]]; then
    error "fail to add remote ${blue}${bold}'${remote_url}'${reset}${bold} to flatpak and flatpak exited with ${red}${bold}$?${reset}${bold} error code"
    exit 10
  fi

  log "starting installation"
  flatpak $command $options $remote $flatpaks 2>&1
  if [[ $? -ne 0 ]]; then
    error "fail to install these flatpaks: ${flatpaks}"
    exit 10
  fi
}

#-----------Main Sequence-----------#

main() {
  local install_fonts=0
  local install_utilities=0
  local install_applications=0
  local install_flatpaks=0

  local configuration_backup="$HOME/.backup"

  local kitty_configuration="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/kitty/kitty.conf"
  local kitty_theme="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/kitty/theme.conf"
  local bashrc="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/bash/.bashrc"

  local starship="https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz"
  local prompt="https://raw.githubusercontent.com/Cromizone/Dotfiles/main/dotfiles/starship/starship.toml"

  elevate
  clear
  intro

  if (( $install_utilities == 1 )); then
    local utilities="bat eza btop cava"

    case "$(get_distribution)" in
      "fedora") utilities="$utilities ffmpeg-free"  ;;
      "debian") utilities="$utilities ffmpeg curl flatpak" ;;
      *) utilities="$utilities ffmpeg" ;;
    esac

    heading "INSTALL" "installing terminal utilities ${dim}${bold}($(printf "%s" "$utilities" | sed "s/ /, /g"))${reset}"
    install_packages $utilities
  fi

  if (( $install_applications == 1 )); then
    local desktop=""
    local applications="kitty gparted timeshift"

    if [[ $DESKTOP_SESSION ]]; then
      desktop=${DESKTOP_SESSION##*/}
    elif [[ $GNOME_DESKTOP_SESSION_ID ]]; then
      desktop="gnome"
    elif [[ $MATE_DESKTOP_SESSION_ID ]]; then
      desktop="mate"
    fi

    if [[ "$desktop" == "gnome" ]]; then
      applications="$applications gnome-tweaks"
    else
      applications="$applications lxappearance"
    fi

    case "$(get_distribution)" in
      "debian") utilities="$utilities" ;;
      *) utilities="$utilities grub-customizer" ;;
    esac

    heading "INSTALL" "installing graphical applications ${dim}${bold}($(printf "%s" "$applications" | sed "s/ /, /g"))${reset}"
    install_packages $applications
  fi

  if (( $install_flatpaks == 1 )); then
    local flatpaks="flatseal warehouse codium postman"
    local flatpak_refs="com.github.tchx84.Flatseal io.github.flattool.Warehouse com.vscodium.codium com.getpostman.Postman"

    heading "INSTALL" "installing flatpak applications ${dim}${bold}($(printf "%s" "$flatpaks" | sed "s/ /, /g"))"
    install_flatpaks "$flatpak_refs"
  fi

  if (( $install_fonts == 1 )); then
    install_font "SourceCodePro" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/SourceCodePro.tar.xz"
    install_font "JetBrainsMono" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
    install_font "FiraCode" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz"
    install_font "Roboto" "https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-unhinted.zip"
    install_font "Inter" "https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip"
  fi

  if [[ ! -z "$prompt" ]]; then
    heading "CONFIG" "installing and configuring starship prompt"

    local filename=$(basename -- "$starship")
    local tempfile=$(mktemp -t "starship.XXX.$filename")

    log "download ${bold}${green}'${filename}'${reset} from ${bold}${blue}'${starship}'${reset}"
    download "$starship" "$tempfile"

    log "extacting ${bold}${green}'${filename}'${reset} into ${bold}${green}'${user_binaries}'${reset}"
    mkdir -p "$user_binaries"
    extract "$tempfile" "$user_binaries"

    if [[ -f "$HOME/.config/starship.toml" ]]; then
      log "existsing starship prompt configuration detected, moving it into ${bold}${green}'${configuration_backup}'${reset}"
      mkdir -p "${configuration_backup}"

      mv "$HOME/.config/starship.toml" "$configuration_backup"
    fi

    log "downloading starship prompt configuration from ${bold}${blue}'${prompt}'${reset}"
    mkdir -p "$HOME/.config"
    download "$prompt" "$HOME/.config/starship.toml"

    rm "$tempfile"
  fi

  if [[ ! -z "$kitty_configuration" ]]; then
    heading "CONFIG" "configuring kitty terminal"

    log "creating kitty configuration directory under ${bold}${green}'$HOME/.config/kitty'${reset}"
    mkdir -p "$HOME/.config/kitty/"

    if [[ -f "$HOME/.config/kitty/kitty.conf" ]]; then
      log "existsing kitty configuration detected, moving it into ${bold}${green}'${configuration_backup}/kitty'${reset}"
      mkdir -p "${configuration_backup}/kitty"

      mv "$HOME/.config/kitty/kitty.conf" "${configuration_backup}/kitty"
    fi

    if [[ -f "$HOME/.config/kitty/theme.conf" ]]; then
      log "existsing kitty theme detected, moving it into ${bold}${green}'${configuration_backup}/kitty'${reset}"
      mkdir -p "${configuration_backup}/kitty"

      mv "$HOME/.config/kitty/theme.conf" "${configuration_backup}/kitty"
    fi

    log "downloading configuration from ${blue}${bold}'${kitty_configuration}'${reset}"
    download "${kitty_configuration}" "${HOME}/.config/kitty/kitty.conf"

    if [[ ! -z "$kitty_theme" ]]; then
      log "downloading theme from ${blue}${bold}'${kitty_theme}'${reset}"
      download "${kitty_theme}" "${HOME}/.config/kitty/theme.conf"
    fi
  fi

  if [[ ! -z "$bashrc" ]]; then
    heading "CONFIG" "configuring bash shell"

    if [[ -f "$HOME/.bashrc" ]]; then
      log "existsing bashrc detected, moving it into ${bold}${green}'${configuration_backup}'${reset}"
      mkdir -p "$configuration_backup"

      mv "$HOME/.bashrc" "$configuration_backup"
    fi

    log "downloading bashrc from ${blue}${bold}'${bashrc}'${reset}"
    download "$bashrc" "${HOME}/.bashrc"
  fi
}

main
