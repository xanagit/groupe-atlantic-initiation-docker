#!/bin/bash

# =============================================================================
# Installation prérequis Atelier Docker - macOS
# Installation si nécessaire: Homebrew, Colima, Git, Node.js 20, jq
# =============================================================================

set -e # Arrêt en cas d'erreur

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_section() { echo -e "\n${YELLOW}==> $1${NC}"; }

# S'arrête si pas sur MacOS
if [[ "$(uname)" != "Darwin" ]]; then
  log_warn "Le script ne fonctionne que sur MacOS => arrêt"
  exit 1
fi

# Homebrew
# --------
log_section "Homebrew"

if ! command -v brew &>/dev/null; then
  log_info "Homebrew non trouvé => installation..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Ajout de Homebrew au PATH
  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  log_info "Homebrew déjà installé => mise à jour..."
  brew update
fi

# Git
# ---
log_section "Git"

if ! command -v git &>/dev/null; then
  log_info "Installation git..."
  brew install git
else
  log_info "git déjà installé: $(git --version)"
fi

# jq
# --
log_section "jq"

if ! command -v jq &>/dev/null; then
  log_info "Installation jq..."
  brew install jq
else
  log_info "jq déjà installé: $(jq --version)"
fi

# Node.js 20
# ----------
log_section "Node.js 20"

# Vérification si nvm ou fnm est déjà installé
NODE_MANAGER=""
if command -v nvm &>/dev/null || [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  NODE_MANAGER="nvm"
elif command -v fnm &>/dev/null; then
  NODE_MANAGER="fnm"
fi

if [[ -n "$NODE_MANAGER" ]]; then
  log_warn "Node version manager détecté: ${NODE_MANAGER}"
  log_warn "Pas d'installation de node via brew pour éviter les conflits"
  log_warn "Merci de lancer manuellement les commandes :"

  if [[ "$NODE_MANAGER" == "nvm" ]]; then
    echo "    nvm install 20"
    echo "    nvm use 20"
    echo "    nvm alias default 20"
  else
    echo "    fnm install 20"
    echo "    fnm use 20"
    echo "    fnm default 20"
  fi

else
  if command -v node &>/dev/null && [[ "$(node --version | cut -d. -f1 | tr -d 'v')" == "20" ]]; then
    log_info "Node.js 20 est déjà installé: $(node --version)"
  else
    log_info "Installation de Node.js 20 avec Homebrew..."
    brew install node@20

    # Défini node@20 comme la version node par défaut dans le PATH
    brew link --overwrite --force node@20

    # Ajoute node@20 au PATH pour la session courante
    export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
  fi
fi

# Colima (runtime Docker pour macOS)
# =============================================================================
log_section "Colima + Docker CLI"

# Colima requires the docker CLI to be installed separately
if ! command -v docker &>/dev/null; then
  log_info "Installation de Docker CLI..."
  brew install docker
else
  log_info "Docker CLI est déjà installé: $(docker --version)"
fi

if ! command -v colima &>/dev/null; then
  log_info "Installation Colima..."
  brew install colima
else
  log_info "Colima est déjà installed: $(colima version)"
fi

if ! colima status &>/dev/null 2>&1; then
  log_info "Démarrage de Colima..."
  colima start
else
  log_info "Colima est déjà lancé"
fi

# =============================================================================
# Summary
# =============================================================================
log_section "Installation terminée :"

echo ""
printf "  %-15s %s\n" "git:" "$(git --version)"
printf "  %-15s %s\n" "jq:" "$(jq --version)"
printf "  %-15s %s\n" "node:" "$(node --version 2>/dev/null || echo 'pas dans le PATH -> redémarrer terminal')"
printf "  %-15s %s\n" "npm:" "$(npm --version 2>/dev/null || echo 'pas dans le PATH -> redémarrer terminal')"
printf "  %-15s %s\n" "docker:" "$(docker --version)"
printf "  %-15s %s\n" "colima:" "$(colima version)"
echo ""
