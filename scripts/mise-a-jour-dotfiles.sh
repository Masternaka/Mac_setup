# Fonctions Bash 3.2 appelées par zsh-setup.sh pour mettre à jour Mac_dotfiles.
# Le lanceur fournit run(), la journalisation et le chemin du clone.

check_clean_dotfiles() {
    local changes
    changes="$(git --no-optional-locks -C "$DOTFILES" status --porcelain=v1 --untracked-files=all)" || return 1
    if [ -n "$changes" ]; then
        log_error "Mac_dotfiles contient des modifications locales : $DOTFILES"
        printf '%s\n' "$changes" >&2
        return 1
    fi
}

check_fast_forward() {
    if git -C "$DOTFILES" merge-base --is-ancestor "$1" "$2"; then
        return 0
    fi
    if git -C "$DOTFILES" merge-base --is-ancestor "$2" "$1"; then
        log_warn 'La branche locale est en avance sur la branche distante.'
    else
        log_error 'La branche locale ne peut pas avancer directement vers la branche distante.'
    fi
    return 1
}

update_dotfiles() (
    local root branch initial_commit remote remote_ref response remote_commit response_ref fetched_commit backup
    # Empêcher la lecture d’un objet absent de déclencher un téléchargement.
    export GIT_NO_LAZY_FETCH=1
    if [ "$CLONE_NEEDED" -eq 1 ]; then
        log_error "Clone Mac_dotfiles absent : $DOTFILES"
        return 1
    fi
    if ! root="$(git -C "$DOTFILES" rev-parse --show-toplevel 2>/dev/null)" || [ "$root" != "$DOTFILES" ]; then
        log_error "Un clone Git est attendu à cet emplacement : $DOTFILES"
        return 1
    fi
    if ! branch="$(git -C "$DOTFILES" symbolic-ref --quiet --short HEAD)"; then
        log_error "Sélectionnez une branche dans Mac_dotfiles avant la mise à jour : $DOTFILES"
        return 1
    fi
    check_clean_dotfiles || return 1
    initial_commit="$(git -C "$DOTFILES" rev-parse --verify HEAD)" || return 1
    remote="$(git -C "$DOTFILES" config --get "branch.$branch.remote")" || remote=""
    remote_ref="$(git -C "$DOTFILES" config --get-all "branch.$branch.merge")" || remote_ref=""
    if [ -z "$remote" ] || [ "$remote" = . ] || [[ "$remote_ref" != refs/heads/* ]] ||
        ! git check-ref-format "$remote_ref"; then
        log_error "La branche $branch doit suivre une seule branche distante."
        return 1
    fi

    log_info "Mac_dotfiles : $branch suit $remote/${remote_ref#refs/heads/}."
    if ! response="$(git -C "$DOTFILES" ls-remote --exit-code --refs -- "$remote" "$remote_ref")" ||
        ! IFS=$'\t' read -r remote_commit response_ref <<< "$response" ||
        [ "$response_ref" != "$remote_ref" ] || [[ ! "$remote_commit" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
        log_error "Impossible de lire la branche distante : $remote/$remote_ref"
        return 1
    fi
    if [ "$initial_commit" = "$remote_commit" ]; then
        log_ok 'Mac_dotfiles est à jour.'
        return 0
    fi

    if git -C "$DOTFILES" cat-file -e "${remote_commit}^{commit}" 2>/dev/null; then
        check_fast_forward "$initial_commit" "$remote_commit" || return 1
        log_info 'Mise à jour disponible en avance rapide.'
    else
        log_info 'La branche distante a changé. L’avance rapide sera vérifiée après récupération.'
    fi
    log_info "Révision locale : $initial_commit"
    log_info "Révision distante : $remote_commit"
    [ "$DRY_RUN" -eq 0 ] || return 0

    run git -C "$DOTFILES" fetch --no-tags --no-recurse-submodules -- "$remote" "$remote_ref" || return $?
    fetched_commit="$(git -C "$DOTFILES" rev-parse --verify 'FETCH_HEAD^{commit}')" || return 1
    if [ "$fetched_commit" != "$remote_commit" ]; then
        log_error 'La branche distante a changé pendant la récupération. Relancez la simulation.'
        return 1
    fi
    check_fast_forward "$initial_commit" "$fetched_commit" || return 1
    backup="$(run mktemp -d "$HOME/.mac-setup-dotfiles.$(date +%Y%m%d-%H%M%S).XXXXXXXX")" || return 1
    run git -C "$DOTFILES" archive --format=tar --output="$backup/mac-dotfiles.tar" "$initial_commit" || return $?
    log_info "Sauvegarde des configurations de départ : $backup/mac-dotfiles.tar"
    if [ "$(git -C "$DOTFILES" symbolic-ref --quiet --short HEAD)" != "$branch" ] ||
        [ "$(git -C "$DOTFILES" rev-parse --verify HEAD)" != "$initial_commit" ]; then
        log_error 'La branche locale a changé pendant la récupération. Relancez la simulation.'
        return 1
    fi
    check_clean_dotfiles || return 1
    run git -C "$DOTFILES" merge --ff-only --no-autostash --no-overwrite-ignore "$fetched_commit" || return $?
    log_ok 'Mac_dotfiles a été mis à jour en avance rapide.'
)
