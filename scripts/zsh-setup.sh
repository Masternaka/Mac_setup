#!/usr/bin/env bash
# Objectif : préparer Zsh, Ghostty, Yazi et Bat à partir de Mac_dotfiles.
# Prérequis : macOS, Bash 3.2+, Homebrew, Git, cksum et applications sélectionnées.
# Options : --dotfiles CHEMIN, --packages LISTE, --prepare, --status,
#           --update-dotfiles, --dry-run, --apply, --help.
# Effets : installe les outils et plugins absents, sauvegarde et lie les réglages.
# Retour arrière : voir les sauvegardes et la liste des liens, puis le README.

set -euo pipefail

DRY_RUN=1
ACTION=deploy
DOTFILES=""
DOTFILES_URL="https://github.com/Masternaka/Mac_dotfiles.git"
CLONE_NEEDED=0
BREW_PREFIX=""
HISTORY_PLUGIN=zsh-history-substring-search
TOOL_COMMANDS=(stow fzf zoxide starship eza yazi bat rg fd)
ZSH_PLUGINS=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf-tab)
PACKAGES=()
MISSING_FORMULAS=()
MISSING_PLUGINS=()
APPLY_FORMULAS=()
APPLY_FORMULAS_CHECKED=0
APPLY_PLUGINS_CHECKED=0
APPLY_STEP="vérification des prérequis"
APPLY_CLONE="non vérifié"
APPLY_STOW="non lancé"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=deploiement-stow.sh
source "$SCRIPT_DIR/deploiement-stow.sh"

usage() {
    cat <<'EOF'
Usage : bash scripts/zsh-setup.sh [options]

Prépare les outils et plugins du terminal, puis déploie avec GNU Stow
les configurations de Zsh, Ghostty, Yazi, Bat et Starship.

  --dotfiles CHEMIN  Clone local de Mac_dotfiles (par défaut, dépôt voisin)
  --packages LISTE   Paquets séparés par des virgules (par défaut, les cinq)
  --dry-run         Affiche les actions prévues (défaut)
  --apply           Installe les éléments manquants et déploie sur le Mac cible
  --prepare         Limite l'action à la préparation des outils, plugins et clone
  --status          Affiche l'état actuel des outils, plugins et liens en lecture seule
  --update-dotfiles Compare le clone avec sa branche distante et le met à jour avec --apply
  -h, --help        Affiche cette aide

Choisissez un seul mode : --dry-run ou --apply.
--prepare s'utilise seul pour simuler ou avec --apply pour préparer le Mac cible.
--status est incompatible avec --prepare et --apply.
--update-dotfiles est une action distincte et s'applique au clone entier.
Homebrew et Git doivent être présents. Ghostty est requis pour son paquet.
Paquets disponibles : zsh, ghostty, yazi, bat, starship.
EOF
}

log() {
    local level="$1" color="$2" reset=""
    shift 2
    if [ -t 1 ]; then
        reset=$'\033[0m'
    else
        color=""
    fi
    printf '%s[%s]%s %s\n' "$color" "$level" "$reset" "$*"
}

log_info() { log INFO $'\033[36m' "$@"; }
log_ok() { log OK $'\033[32m' "$@"; }
log_warn() { log WARN $'\033[33m' "$@"; }
log_error() { log ERREUR $'\033[31m' "$@" >&2; }

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[SIMULATION]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

package_selected() {
    local package
    for package in ${PACKAGES[@]+"${PACKAGES[@]}"}; do
        if [ "$package" = "$1" ]; then
            return 0
        fi
    done
    return 1
}

add_packages() {
    local list="$1" package
    while :; do
        package="${list%%,*}"
        case "$package" in
            zsh|ghostty|yazi|bat|starship) ;;
            '') log_error 'Paquet vide dans --packages.'; return 2 ;;
            *) log_error "Paquet inconnu dans --packages : $package"; return 2 ;;
        esac
        if ! package_selected "$package"; then
            PACKAGES+=("$package")
        fi
        [[ "$list" = *,* ]] || return 0
        list="${list#*,}"
    done
}

parse_args() {
    local mode="" help_requested=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dotfiles)
                if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" = --* ]]; then
                    log_error 'Indiquez le chemin du clone après --dotfiles.'
                    exit 2
                fi
                DOTFILES="$2"
                shift
                ;;
            --packages)
                if [ "$#" -lt 2 ] || [[ "$2" = --* ]]; then
                    log_error 'Indiquez les paquets après --packages.'
                    exit 2
                fi
                add_packages "$2" || exit 2
                shift
                ;;
            --packages=*) add_packages "${1#*=}" || exit 2 ;;
            --dry-run|--apply)
                if [ -n "$mode" ] && [ "$mode" != "$1" ]; then
                    log_error 'Les options --dry-run et --apply sont incompatibles. Choisissez un seul mode.'
                    exit 2
                fi
                mode="$1"
                ;;
            --prepare|--status|--update-dotfiles)
                if [ "$ACTION" != deploy ] && [ "$ACTION" != "${1#--}" ]; then
                    log_error "Les options --$ACTION et $1 sont incompatibles."
                    exit 2
                fi
                ACTION="${1#--}"
                ;;
            -h|--help) help_requested=1 ;;
            *) log_error "Option inconnue : $1"; exit 2 ;;
        esac
        shift
    done
    if [ "$ACTION" = status ] && [ "$mode" = --apply ]; then
        log_error 'Les options --status et --apply sont incompatibles.'
        exit 2
    fi
    if [ "$ACTION" = update-dotfiles ] && [ -n "${PACKAGES[0]:-}" ]; then
        log_error 'Les options --update-dotfiles et --packages sont incompatibles.'
        exit 2
    fi
    if [ "$help_requested" -eq 1 ]; then
        usage
        exit 0
    fi
    if [ "$mode" = --apply ]; then
        DRY_RUN=0
    fi
    if [ -z "${PACKAGES[0]:-}" ]; then
        PACKAGES=(zsh ghostty yazi bat starship)
    fi
}

locate_dotfiles() {
    local parent destination
    if [ -z "$DOTFILES" ]; then
        DOTFILES="$SCRIPT_DIR/../../Mac_dotfiles"
    fi
    if [ -d "$DOTFILES" ]; then
        if ! destination="$(CDPATH= cd -- "$DOTFILES" && pwd -P)"; then
            log_error "Impossible d’accéder à $DOTFILES."
            return 1
        fi
        DOTFILES="$destination"
    else
        if [ -e "$DOTFILES" ] || [ -L "$DOTFILES" ]; then
            log_error "L’emplacement est occupé : $DOTFILES"
            return 1
        fi
        if ! parent="$(CDPATH= cd -- "$(dirname -- "$DOTFILES")" 2>/dev/null && pwd -P)"; then
            log_error "Le dossier parent de $DOTFILES doit exister."
            return 1
        fi
        DOTFILES="${parent%/}/$(basename -- "$DOTFILES")"
        CLONE_NEEDED=1
    fi
}

clone_dotfiles() {
    log_info "Clonage de Mac_dotfiles dans $DOTFILES"
    run git clone -- "$DOTFILES_URL" "$DOTFILES"
}

use_existing_tools() {
    local directory
    # Compléter le PATH de ce processus pour les lancements hors de Ghostty.
    if ! command -v brew >/dev/null 2>&1 && [ -x /opt/homebrew/bin/brew ]; then
        export PATH="$PATH:/opt/homebrew/bin"
    fi
    if ! command -v brew >/dev/null 2>&1 && [ -x /usr/local/bin/brew ]; then
        export PATH="$PATH:/usr/local/bin"
    fi
    if command -v brew >/dev/null 2>&1; then
        if BREW_PREFIX="$(brew --prefix 2>/dev/null)" && [[ "$BREW_PREFIX" = /* ]]; then
            export PATH="$PATH:$BREW_PREFIX/bin"
            if ! command -v stow >/dev/null 2>&1 && [ -x "$BREW_PREFIX/opt/stow/bin/stow" ]; then
                export PATH="$PATH:$BREW_PREFIX/opt/stow/bin"
            fi
        else
            BREW_PREFIX=""
        fi
    fi
    if command -v ghostty >/dev/null 2>&1; then
        return 0
    fi
    for directory in /Applications/Ghostty.app/Contents/MacOS "$HOME/Applications/Ghostty.app/Contents/MacOS"; do
        if [ -x "$directory/ghostty" ]; then
            export PATH="$PATH:$directory"
            return 0
        fi
    done
}

collect_formulas() {
    local tool formula
    MISSING_FORMULAS=()
    for tool in "${TOOL_COMMANDS[@]}"; do
        case "$tool" in
            fzf|zoxide|eza|rg|fd) package_selected zsh || continue ;;
            starship|yazi|bat) package_selected "$tool" || continue ;;
        esac
        formula="$tool"
        if [ "$tool" = rg ]; then
            formula=ripgrep
        fi
        if ! command -v "$tool" >/dev/null 2>&1; then
            MISSING_FORMULAS+=("$formula")
        fi
    done
    if package_selected zsh && ! history_plugin_available; then
        MISSING_FORMULAS+=("$HISTORY_PLUGIN")
    fi
}

install_formulas() {
    if [ -n "${MISSING_FORMULAS[0]:-}" ]; then
        log_info "Formules Homebrew à préparer : ${MISSING_FORMULAS[*]}"
        run env HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
            HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install --formula "${MISSING_FORMULAS[@]}"
    fi
}

plugin_available() {
    local plugin="$1" directory="$HOME/.zsh/$1"
    case "$plugin" in
        zsh-completions) [ -d "$directory/src" ] && [ -r "$directory/src" ] && [ -x "$directory/src" ] ;;
        fzf-tab) [ -f "$directory/fzf-tab.plugin.zsh" ] && [ -r "$directory/fzf-tab.plugin.zsh" ] ;;
        *) [ -f "$directory/$plugin.zsh" ] && [ -r "$directory/$plugin.zsh" ] ;;
    esac
}

history_plugin_available() {
    [ -n "$BREW_PREFIX" ] && [ -r "$BREW_PREFIX/share/$HISTORY_PLUGIN/$HISTORY_PLUGIN.zsh" ]
}

plan_plugins() {
    local plugin directory="$HOME/.zsh" destination
    for plugin in "${ZSH_PLUGINS[@]}"; do
        destination="$directory/$plugin"
        if plugin_available "$plugin"; then
            log_ok "$plugin déjà disponible"
        elif [ -e "$destination" ] || [ -L "$destination" ]; then
            log_error "Plugin incomplet à vérifier : $destination"
            return 1
        else
            MISSING_PLUGINS+=("$plugin")
        fi
    done
    if [ -n "${MISSING_PLUGINS[0]:-}" ] && { [ -L "$directory" ] || { [ -e "$directory" ] && [ ! -d "$directory" ]; }; }; then
        log_error "Dossier des plugins incompatible : $directory"
        return 1
    fi
}

install_plugins() {
    local plugin owner destination
    [ -n "${MISSING_PLUGINS[0]:-}" ] || return 0
    run mkdir -p -- "$HOME/.zsh"
    for plugin in "${MISSING_PLUGINS[@]}"; do
        owner=zsh-users
        if [ "$plugin" = fzf-tab ]; then
            owner=Aloxaf
        fi
        destination="$HOME/.zsh/$plugin"
        run git clone -- "https://github.com/$owner/$plugin.git" "$destination"
        if [ "$DRY_RUN" -eq 0 ] && ! plugin_available "$plugin"; then
            log_error "Le clone de $plugin est incomplet : $destination"
            return 1
        fi
    done
}

report_ghostty_overrides() {
    local directory file
    directory="$HOME/Library/Application Support/com.mitchellh.ghostty"
    for file in "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config.ghostty" \
        "$directory/config" "$directory/config.ghostty"; do
        if [ -f "$file" ]; then
            log_warn "Autre fichier lu par Ghostty : $file. Vérifiez les réglages qui figurent dans les deux fichiers."
        fi
    done
}

report_stow_simulation() {
    local status
    local -a missing
    missing=()
    if [ "$CLONE_NEEDED" -eq 1 ]; then
        missing+=("clone Mac_dotfiles ($DOTFILES)")
    fi
    if ! command -v stow >/dev/null 2>&1; then
        missing+=("GNU Stow")
    fi
    if [ -n "${missing[0]:-}" ]; then
        log_warn 'Liens Stow : vérification reportée'
        printf '  Manquant : %s\n' "${missing[@]}"
        return 0
    fi

    if deploy_with_stow "$@"; then
        log_ok 'Liens Stow : vérifiés'
    else
        status=$?
        log_error 'Liens Stow : vérification échouée'
        return "$status"
    fi
}

report_status() {
    local tool path plugin
    log_info 'Outils du terminal'
    for tool in zsh ghostty brew git cksum "${TOOL_COMMANDS[@]}"; do
        if path="$(command -v "$tool")"; then
            log_ok "$tool : $path"
        else
            log_warn "$tool : absent"
        fi
    done
    log_info 'Plugins Zsh'
    for plugin in "${ZSH_PLUGINS[@]}"; do
        if plugin_available "$plugin"; then
            log_ok "$plugin : disponible"
        else
            log_warn "$plugin : absent ou incomplet"
        fi
    done
    if history_plugin_available; then
        log_ok "$HISTORY_PLUGIN : disponible"
    else
        log_warn "$HISTORY_PLUGIN : absent ou inaccessible via Homebrew"
    fi
    report_ghostty_overrides
    report_configuration_status "$@"
}

require_git() {
    local git_path
    if ! git_path="$(command -v git)" || { [ "$git_path" = /usr/bin/git ] && ! xcode-select -p >/dev/null 2>&1; }; then
        log_error 'Git doit être configuré sur le Mac cible.'
        return 1
    fi
}

report_apply_formulas() {
    local formula
    if [ "$APPLY_FORMULAS_CHECKED" -eq 0 ]; then
        log_info 'Homebrew : outils non vérifiés'
    elif [ -z "${APPLY_FORMULAS[0]:-}" ]; then
        log_ok 'Homebrew : outils déjà présents'
    else
        collect_formulas
        for formula in "${APPLY_FORMULAS[@]}"; do
            case " ${MISSING_FORMULAS[*]:-} " in
                *" $formula "*) log_warn "Homebrew : $formula reste indisponible" ;;
                *) log_ok "Homebrew : $formula est maintenant disponible" ;;
            esac
        done
    fi
}

report_apply_plugins() {
    local plugin
    if ! package_selected zsh; then
        log_info 'Plugins Zsh : hors sélection'
    elif [ "$APPLY_PLUGINS_CHECKED" -eq 0 ]; then
        log_info 'Plugins Zsh : vérification incomplète'
    elif [ -z "${MISSING_PLUGINS[0]:-}" ]; then
        log_ok 'Plugins Zsh : déjà présents'
    else
        for plugin in "${MISSING_PLUGINS[@]}"; do
            if plugin_available "$plugin"; then
                log_ok "Plugins Zsh : $plugin est maintenant disponible"
            else
                log_warn "Plugins Zsh : $plugin reste absent ou incomplet"
            fi
        done
    fi
}

report_apply_summary() {
    local status="$1"
    log_info 'Bilan de l’application'
    if [ "$status" -eq 0 ]; then
        log_ok 'Opération terminée'
    else
        log_error "Arrêt à l’étape « $APPLY_STEP » (code $status)."
    fi
    log_info "Paquets : ${PACKAGES[*]}"
    log_info "Mac_dotfiles : $APPLY_CLONE"
    report_apply_formulas
    report_apply_plugins
    log_info "Déploiement Stow : $APPLY_STOW"
}

main() {
    local tool
    local -a required_tools
    parse_args "$@"
    if [ "$DRY_RUN" -eq 0 ] && [[ "$ACTION" = deploy || "$ACTION" = prepare ]]; then
        trap 'report_apply_summary "$?"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        if [ "$ACTION" = prepare ]; then
            APPLY_STOW="hors préparation"
        fi
    fi
    if [ "$(uname -s)" != Darwin ]; then
        log_error 'Ce script est destiné à macOS.'
        return 1
    fi
    : "${HOME:?Répertoire personnel introuvable}"
    if [ "$ACTION" = update-dotfiles ]; then
        require_git
        locate_dotfiles
        # shellcheck source=mise-a-jour-dotfiles.sh
        source "$SCRIPT_DIR/mise-a-jour-dotfiles.sh"
        update_dotfiles
        return $?
    fi
    use_existing_tools
    if [ "$ACTION" = status ]; then
        locate_dotfiles
        report_status "${PACKAGES[@]}"
        return $?
    fi
    required_tools=(brew cksum)
    if package_selected zsh; then
        required_tools+=(zsh)
    fi
    if package_selected ghostty; then
        required_tools+=(ghostty)
    fi
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "$tool doit déjà être disponible sur le Mac cible."
            return 1
        fi
    done
    require_git
    if [ -z "$BREW_PREFIX" ]; then
        log_error 'Impossible de déterminer le préfixe Homebrew.'
        return 1
    fi

    APPLY_STEP="recherche du clone Mac_dotfiles"
    locate_dotfiles
    if [ "$CLONE_NEEDED" -eq 1 ]; then
        APPLY_CLONE="absent ($DOTFILES)"
    else
        APPLY_CLONE="clone existant ($DOTFILES)"
    fi
    if [ "$ACTION" = deploy ] && [ "$DRY_RUN" -eq 0 ]; then
        APPLY_STEP="vérification préalable de Stow"
        APPLY_STOW="vérification préalable interrompue"
        if [ "$CLONE_NEEDED" -eq 0 ] && command -v stow >/dev/null 2>&1; then
            log_info 'Vérification des liens Stow avant installation.'
            (DRY_RUN=1; deploy_with_stow "${PACKAGES[@]}") || return $?
            APPLY_STOW="liens vérifiés, déploiement non lancé"
        else
            check_stow_environment
            APPLY_STOW="déploiement non lancé"
        fi
    fi
    if package_selected zsh; then
        APPLY_STEP="vérification des plugins Zsh"
        plan_plugins
        APPLY_PLUGINS_CHECKED=1
    fi
    if [ "$ACTION" = deploy ] && package_selected ghostty; then
        report_ghostty_overrides
    fi
    if [ "$CLONE_NEEDED" -eq 1 ]; then
        APPLY_STEP="clonage de Mac_dotfiles"
        APPLY_CLONE="clonage interrompu ($DOTFILES)"
        clone_dotfiles
        APPLY_CLONE="clone créé ($DOTFILES)"
    fi
    APPLY_STEP="installation des outils Homebrew"
    collect_formulas
    if [ "$DRY_RUN" -eq 0 ]; then
        APPLY_FORMULAS=(${MISSING_FORMULAS[@]+"${MISSING_FORMULAS[@]}"})
        APPLY_FORMULAS_CHECKED=1
    fi
    install_formulas
    if [ "$DRY_RUN" -eq 0 ]; then
        use_existing_tools
        collect_formulas
        if [ -n "${MISSING_FORMULAS[0]:-}" ]; then
            log_error "Outils encore indisponibles après Homebrew : ${MISSING_FORMULAS[*]}"
            return 1
        fi
    fi
    if package_selected zsh; then
        APPLY_STEP="clonage des plugins Zsh"
        if command -v fzf >/dev/null 2>&1 && ! fzf --zsh >/dev/null 2>&1; then
            log_warn "La version actuelle de fzf ne fournit pas --zsh. Les raccourcis de fzf demandent une version récente."
        fi
        install_plugins
    fi

    log_info "Configuration de référence : $DOTFILES"
    if [ "$ACTION" = prepare ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info 'Préparation simulée. Utilisez --prepare --apply pour préparer le Mac cible.'
        else
            log_ok 'Outils, plugins et clone prêts. Lancez --dry-run pour vérifier les liens Stow.'
        fi
        return 0
    fi
    log_info "Configurations sélectionnées : ${PACKAGES[*]}"
    if [ "$DRY_RUN" -eq 1 ]; then
        report_stow_simulation "${PACKAGES[@]}"
    else
        APPLY_STEP="déploiement Stow"
        APPLY_STOW="déploiement interrompu"
        deploy_with_stow "${PACKAGES[@]}"
        APPLY_STOW="terminé"
        log_ok 'Préparation terminée. Relancez Ghostty pour charger les réglages.'
    fi
}

main "$@"
