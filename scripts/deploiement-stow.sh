# Fonctions Bash 3.2 appelées par zsh-setup.sh pour déployer les configurations.
# Le lanceur fournit run(), package_selected(), la journalisation et les options.

TARGET_HOME=""
BACKUP_DIR=""
LOCK_DIR=""
STOW_STARTED=0
PLAN_SOURCES=()
PLAN_PATHS=()
PLAN_STATES=()
PLAN_CHECKSUMS=()
RESTORED_PATHS=()

check_stow_environment() {
    local path
    TARGET_HOME="$(CDPATH= cd -- "$HOME" && pwd -P)" || return 1
    case "$TARGET_HOME/" in
        /|//|"$DOTFILES/"*) log_error "Répertoire personnel incorrect : $TARGET_HOME"; return 1 ;;
    esac
    for path in "$HOME/.stowrc" "$DOTFILES/.stowrc"; do
        if [ -e "$path" ] || [ -L "$path" ]; then
            log_error "Les options implicites de Stow doivent être écartées : $path"
            return 1
        fi
    done
    if package_selected zsh && [ -n "${ZDOTDIR:-}" ] &&
        [ "${ZDOTDIR%/}" != "${HOME%/}" ] && [ "${ZDOTDIR%/}" != "$TARGET_HOME" ]; then
        log_error "ZDOTDIR cible un emplacement différent de $TARGET_HOME."
        return 1
    fi
    if [ -n "${XDG_CONFIG_HOME:-}" ] && [ "${XDG_CONFIG_HOME%/}" != "${HOME%/}/.config" ] &&
        [ "${XDG_CONFIG_HOME%/}" != "$TARGET_HOME/.config" ]; then
        log_error "XDG_CONFIG_HOME cible un emplacement différent de $TARGET_HOME/.config."
        return 1
    fi
    if package_selected yazi && [ -n "${YAZI_CONFIG_HOME:-}" ] && [ "${YAZI_CONFIG_HOME%/}" != "${HOME%/}/.config/yazi" ] &&
        [ "${YAZI_CONFIG_HOME%/}" != "$TARGET_HOME/.config/yazi" ]; then
        log_warn "Yazi utilise un autre dossier : $YAZI_CONFIG_HOME"
    fi
    if package_selected bat && [ -n "${BAT_CONFIG_PATH:-}" ] && [ "$BAT_CONFIG_PATH" != "${HOME%/}/.config/bat/config" ] &&
        [ "$BAT_CONFIG_PATH" != "$TARGET_HOME/.config/bat/config" ]; then
        log_warn "Bat utilise un autre fichier : $BAT_CONFIG_PATH"
    fi
}

check_parents() {
    local relative="$1" source="$2" parent
    parent="$TARGET_HOME"
    while [[ "$relative" == */* ]]; do
        parent="$parent/${relative%%/*}"
        relative="${relative#*/}"
        if [ -L "$parent" ]; then
            # Un ancien dossier replié par Stow est acceptable seulement si
            # le fichier est déjà en place et ne doit subir aucune écriture.
            if [ -n "$source" ] && [ "$TARGET_HOME/$1" -ef "$source" ]; then
                return 0
            fi
            log_error "Dossier parent symbolique : $parent"
            return 1
        fi
        if [ -e "$parent" ] && [ ! -d "$parent" ]; then
            log_error "Dossier parent occupé par un fichier : $parent"
            return 1
        fi
    done
}

plan_file() {
    local source="$1" relative="$2" target="$TARGET_HOME/$2" state=nouveau checksum="" existing
    for existing in ${PLAN_PATHS[@]+"${PLAN_PATHS[@]}"}; do
        if [ "$existing" = "$relative" ]; then
            log_error "Deux paquets ciblent le même fichier : $relative"
            return 1
        fi
    done
    check_parents "$relative" "$source" || return 1
    if [ "$target" -ef "$source" ]; then
        state=conserve
    elif [ -L "$target" ] || { [ -e "$target" ] && [ ! -f "$target" ]; }; then
        log_error "Destination en conflit : $target"
        return 1
    elif [ -f "$target" ]; then
        state=sauvegarde
        checksum="$(cksum < "$target")" || return 1
    fi
    PLAN_PATHS+=("$relative")
    PLAN_SOURCES+=("$source")
    PLAN_STATES+=("$state")
    PLAN_CHECKSUMS+=("$checksum")
    log_info "$state : $target"
}

required_configurations() {
    case "$1" in
        zsh) printf '%s\n' .zshrc .config/zsh/{10-environnement,20-historique,30-completion,40-outils,50-recherche,60-edition,70-alias}.zsh ;;
        ghostty) printf '%s\n' .config/ghostty/config ;;
        yazi) printf '%s\n' .config/yazi/yazi.toml .config/yazi/keymap.toml ;;
        bat) printf '%s\n' .config/bat/config ;;
        starship) printf '%s\n' .config/starship.toml .config/starship-latte.toml ;;
        *) log_error "Paquet inattendu : $1"; return 1 ;;
    esac
}

report_configuration_status() {
    local package required relative target source
    if [ "$CLONE_NEEDED" -eq 1 ]; then
        log_warn "Clone Mac_dotfiles absent : $DOTFILES"
    else
        log_info "Configuration de référence : $DOTFILES"
    fi

    for package in "$@"; do
        log_info "Fichiers du paquet $package"
        required="$(required_configurations "$package")" || return 1
        while IFS= read -r relative; do
            target="${HOME%/}/$relative"
            source="$DOTFILES/$package/$relative"
            if [ -L "$target" ] && [ ! -e "$target" ]; then
                log_warn "Lien cassé : $target"
            elif [ ! -f "$source" ] || [ ! -r "$source" ]; then
                log_warn "Source indisponible pour $target : $source"
            elif [ "$target" -ef "$source" ]; then
                log_ok "Source en place : $target"
            elif [ -L "$target" ]; then
                log_warn "Lien vers une autre source : $target"
            elif [ -e "$target" ]; then
                log_warn "Destination locale : $target"
            else
                log_warn "Destination absente : $target"
            fi
        done <<< "$required"
    done
}

plan_package() {
    local package="$1" root="$DOTFILES/$1" expected required relative source complete=0
    expected="$(required_configurations "$package")" || return 1
    if [ ! -d "$root" ] || [ -L "$root" ]; then
        log_error "Paquet introuvable ou symbolique : $root"
        return 1
    fi
    while IFS= read -r required; do
        if [ ! -f "$root/$required" ] || [ ! -r "$root/$required" ]; then
            log_error "Configuration requise : $root/$required"
            return 1
        fi
    done <<< "$expected"
    while IFS= read -r -d '' source; do
        if [ -z "$source" ]; then
            complete=1
            break
        fi
        relative="${source#"$root/"}"
        case "$relative" in
            *$'\n'*|*$'\r'*|*$'\t'*) log_error "Nom de fichier non pris en charge dans $root"; return 1 ;;
        esac
        if [ -L "$source" ]; then
            log_error "Source symbolique : $source"
            return 1
        fi
        case "$relative" in
            README.md|.stow-local-ignore|.DS_Store|*/.DS_Store)
                [ -f "$source" ] || { log_error "Fichier de dépôt incorrect : $source"; return 1; }
                continue
                ;;
        esac
        case "$package:$relative" in
            zsh:.zshrc|zsh:.config/zsh/*|ghostty:.config/ghostty/*|yazi:.config/yazi/*|bat:.config/bat/*|starship:.config/starship.toml|starship:.config/starship-latte.toml)
                if [ -d "$source" ]; then
                    continue
                fi
                if [ ! -f "$source" ] || [ ! -r "$source" ]; then
                    log_error "Source illisible ou non prise en charge : $source"
                    return 1
                fi
                plan_file "$source" "$relative" || return 1
                ;;
            *:.config|zsh:.config/zsh|ghostty:.config/ghostty|yazi:.config/yazi|bat:.config/bat)
                [ -d "$source" ] || { log_error "Un dossier est attendu : $source"; return 1; }
                ;;
            *) log_error "Chemin hors du paquet attendu : $source"; return 1 ;;
        esac
    done < <(find "$root" -mindepth 1 -print0 && printf '\0')
    [ "$complete" -eq 1 ] || { log_error "Lecture incomplète du paquet $package"; return 1; }
}

write_manifest() {
    local index
    for ((index=0; index<${#PLAN_PATHS[@]}; index++)); do
        printf '%s\t%s\t%s\n' "${PLAN_STATES[index]}" "$TARGET_HOME/${PLAN_PATHS[index]}" "${PLAN_SOURCES[index]}" || return 1
    done > "$BACKUP_DIR/liens.tsv"
}

backup_target() {
    local index="$1" relative="${PLAN_PATHS[$1]}" target backup
    target="$TARGET_HOME/$relative"
    backup="$BACKUP_DIR/fichiers/$relative"
    check_parents "$relative" "" || return 1
    if [ -L "$target" ] || [ ! -f "$target" ] || [ "$(cksum < "$target")" != "${PLAN_CHECKSUMS[index]}" ]; then
        log_error "Le fichier a changé depuis la simulation : $target"
        return 1
    fi
    mkdir -p -- "${backup%/*}" && mv -n -- "$target" "$backup" && [ ! -e "$target" ] && [ ! -L "$target" ]
}

restore_after_failure() {
    local index target relative backup
    for ((index=${#PLAN_PATHS[@]}-1; index>=0; index--)); do
        [ "${PLAN_STATES[index]}" != conserve ] || continue
        relative="${PLAN_PATHS[index]}"
        target="$TARGET_HOME/$relative"
        backup="$BACKUP_DIR/fichiers/$relative"
        check_parents "$relative" "" || continue
        if [ "$STOW_STARTED" -eq 1 ] && [ -L "$target" ] && [ "$target" -ef "${PLAN_SOURCES[index]}" ]; then
            run unlink "$target" || log_error "Lien à vérifier : $target"
        fi
        if [ -f "$backup" ]; then
            if [ ! -e "$target" ] && [ ! -L "$target" ] && run mv -n -- "$backup" "$target" && [ ! -e "$backup" ]; then
                RESTORED_PATHS+=("$target")
            else
                log_error "Fichier à restaurer depuis $backup"
            fi
        fi
    done
}

finish_deployment() {
    local status="$1" target
    trap - EXIT INT TERM
    if [ "$status" -ne 0 ] && [ -n "$BACKUP_DIR" ]; then
        log_warn "Déploiement interrompu. Vérifiez le bilan dans $BACKUP_DIR."
        restore_after_failure
    fi
    run rmdir -- "$LOCK_DIR" || log_warn "Verrou à vérifier : $LOCK_DIR"
    if [ -n "$BACKUP_DIR" ]; then
        log_info 'Bilan Stow'
        log_info "Sauvegardes et liste des liens : $BACKUP_DIR"
        if [ "$status" -ne 0 ]; then
            if [ -n "${RESTORED_PATHS[0]:-}" ]; then
                for target in "${RESTORED_PATHS[@]}"; do
                    log_ok "Fichier restauré : $target"
                done
            else
                log_info 'Aucun fichier restauré.'
            fi
        fi
    fi
    exit "$status"
}

deploy_with_stow() (
    local package index state changed=0
    local -a stow_options
    check_stow_environment || return $?
    cd -- "$DOTFILES" || return $?
    if [ "$DRY_RUN" -eq 0 ]; then
        LOCK_DIR="$TARGET_HOME/.mac-setup-stow.lock"
        if ! run mkdir -m 700 -- "$LOCK_DIR"; then
            log_error "Un déploiement est en cours ou un ancien verrou existe : $LOCK_DIR"
            return 1
        fi
        trap 'finish_deployment "$?"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
    fi
    for package in "$@"; do
        plan_package "$package" || return $?
    done
    stow_options=(--dir="$DOTFILES" --target="$TARGET_HOME" --no-folding
        '--ignore=^(README\.md|\.stow-local-ignore|\.DS_Store)$')
    # --adopt représente les fichiers à sauvegarder pendant la simulation.
    stow "${stow_options[@]}" --simulate --verbose --adopt --stow "$@" || return $?
    [ "$DRY_RUN" -eq 0 ] || return 0
    for state in "${PLAN_STATES[@]}"; do
        [ "$state" = conserve ] || changed=1
    done
    if [ "$changed" -eq 0 ]; then
        log_ok 'Les configurations sont déjà en place.'
        return 0
    fi

    BACKUP_DIR="$(run mktemp -d "$TARGET_HOME/.mac-setup-backup.XXXXXXXX")"
    log_info "Sauvegardes et liste des liens : $BACKUP_DIR"
    run write_manifest
    for ((index=0; index<${#PLAN_PATHS[@]}; index++)); do
        [ "${PLAN_STATES[index]}" = sauvegarde ] || continue
        run backup_target "$index"
    done
    STOW_STARTED=1
    run stow "${stow_options[@]}" --stow "$@"
    for ((index=0; index<${#PLAN_PATHS[@]}; index++)); do
        if [ ! "$TARGET_HOME/${PLAN_PATHS[index]}" -ef "${PLAN_SOURCES[index]}" ]; then
            log_error "Configuration attendue absente : ${PLAN_PATHS[index]}"
            return 1
        fi
    done
    log_ok 'Configurations liées.'
)
