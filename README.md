# Mac_setup

Scripts de préparation, de diagnostic et de déploiement pour macOS.

## Rôle des dépôts

- **Mac_setup** regroupe les scripts et leur mode d’emploi.
- **Mac_dotfiles** fournit les fichiers de configuration de référence, dont le `.zshrc`, les fragments Zsh et les réglages de Ghostty, Yazi, Bat et Starship. [Dépôt Mac_dotfiles](https://github.com/Masternaka/Mac_dotfiles)

## Préparer Zsh, Ghostty, Yazi et Bat

Le [script de préparation](scripts/zsh-setup.sh) cible macOS sur Apple Silicon
et Intel avec Bash 3.2 ou plus récent. Avec `--apply`, il installe les outils
et les plugins manquants, puis appelle GNU Stow pour lier les configurations de
Mac_dotfiles.

| Paquet | Destination |
| --- | --- |
| Zsh | `~/.zshrc` et les fragments dans `~/.config/zsh/` |
| Ghostty | `~/.config/ghostty/config` |
| Yazi | `~/.config/yazi/yazi.toml` et `~/.config/yazi/keymap.toml` |
| Bat | `~/.config/bat/config` |
| Starship | `~/.config/starship.toml` et `~/.config/starship-latte.toml` |

### Prérequis sur le Mac cible

- Homebrew et Git déjà opérationnels, ainsi que `cksum` fourni par macOS.
  Ghostty est requis pour son paquet et Zsh pour le sien. Une connexion aux
  dépôts Homebrew et GitHub est nécessaire pour récupérer les éléments manquants.
- Le script utilise Homebrew pour installer GNU Stow et les outils manquants.
  Les commandes déjà disponibles sont réutilisées. [Formule GNU Stow](https://formulae.brew.sh/formula/stow)

### Plugins Zsh

| Plugin | Fonction | Emplacement attendu par Mac_dotfiles |
| --- | --- | --- |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Suggestions à partir de l’historique | `~/.zsh/zsh-autosuggestions/` |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | Coloration de la commande en cours de saisie | `~/.zsh/zsh-syntax-highlighting/` |
| [zsh-completions](https://github.com/zsh-users/zsh-completions) | Définitions supplémentaires pour la complétion | `~/.zsh/zsh-completions/` |
| [fzf-tab](https://github.com/Aloxaf/fzf-tab) | Filtrage des propositions de Tab avec `fzf` | `~/.zsh/fzf-tab/` |

Le script clone les plugins absents aux emplacements du tableau. Il conserve
les plugins déjà utilisables et signale un dossier incomplet avant d’y écrire.

### Recherche dans l’historique avec les flèches

Le script installe la formule
[`zsh-history-substring-search`](https://formulae.brew.sh/formula/zsh-history-substring-search)
si elle est absente. Le fichier `zsh/.zshrc` de Mac_dotfiles charge le plugin
et configure les touches ↑ et ↓.

Dans une nouvelle fenêtre Ghostty, taper un fragment d’une ancienne commande
puis utiliser ↑ ou ↓. `Ctrl+R` reste disponible pour la recherche avec `fzf`.

### Outils inclus

| Commande | Usage dans le terminal |
| --- | --- |
| `fzf` | Recherche dans l’historique avec Ctrl+R et insertion d’un chemin avec Ctrl+T. Utiliser une version qui fournit `fzf --zsh`. |
| `zoxide` | Navigation par dossier fréquent via le `cd` configuré dans Mac_dotfiles. |
| `starship` | Invite avec contexte Git et thèmes de Mac_dotfiles. |
| `eza`, `bat` | Listes de fichiers, lecture de code et aperçu des fichiers dans fzf. |
| `yazi` | Gestionnaire de fichiers dans le terminal. |
| `rg`, `fd` | Recherche de texte et de fichiers. Les formules Homebrew sont `ripgrep` et `fd`. |

### Préparation et diagnostic

Pour préparer les outils, les plugins et le clone de Mac_dotfiles avant la
première installation, commencer par simuler puis appliquer la préparation :

```bash
bash scripts/zsh-setup.sh --prepare
bash scripts/zsh-setup.sh --prepare --apply
```

La préparation s’arrête après les installations et clonages. Reprendre ensuite
avec `--dry-run` pour voir le plan des liens Stow avant le déploiement.

Pour vérifier la machine plus tard :

```bash
bash scripts/zsh-setup.sh --status
```

Le diagnostic indique les commandes et plugins disponibles, l’emplacement de
Mac_dotfiles et l’état des fichiers de référence des cinq paquets. Il signale
les destinations absentes, les fichiers locaux et les liens cassés ou qui
pointent ailleurs. Il fonctionne en lecture seule, même lorsque GNU Stow
n’est pas installé. Les options `--status` et `--apply` sont incompatibles.

### Simulation et application

Depuis la racine de Mac_setup, lancer la simulation. Par défaut, le script
cherche ou clone Mac_dotfiles à côté de Mac_setup.

La simulation est le mode par défaut. Une commande qui combine `--dry-run`
et `--apply` est rejetée avec le code `2`, quel que soit l’ordre des options,
avant toute installation, tout clonage ou toute écriture.

```bash
bash scripts/zsh-setup.sh --dry-run
```

Pour choisir un autre emplacement, utiliser `--dotfiles` avec le chemin du
clone existant ou à créer. Le dossier parent doit déjà exister.

```bash
bash scripts/zsh-setup.sh --dotfiles "/chemin/vers/Mac_dotfiles" --dry-run
```

La simulation affiche les installations et clonages prévus. Le bilan affiche
`Liens Stow : vérifiés` si la vérification réussit. En cas de conflit, le
chemin concerné est indiqué et la simulation se termine en erreur. Si le clone
de Mac_dotfiles, GNU Stow ou les deux manquent, le bilan affiche
`Liens Stow : vérification reportée` et précise ce qui manque.

Sur le Mac cible, relire le bilan puis appliquer l’ensemble :

```bash
bash scripts/zsh-setup.sh --apply
```

Avec `--apply`, si Mac_dotfiles et GNU Stow sont déjà présents, le script
vérifie les liens avant toute installation Homebrew ou tout clonage de plugin.
Un conflit, par exemple un lien `~/.zshrc` qui pointe vers une autre source,
arrête le script et affiche le chemin. Le script vérifie de nouveau les liens
au moment du déploiement. Il clone Mac_dotfiles et prépare les éléments
manquants au besoin.

### Déployer une sélection de paquets

Par défaut, les cinq paquets sont sélectionnés. Pour déployer seulement Yazi
et Bat, indiquer leurs noms séparés par des virgules :

```bash
bash scripts/zsh-setup.sh --packages yazi,bat --dry-run
bash scripts/zsh-setup.sh --packages yazi,bat --apply
```

Les valeurs acceptées sont `zsh`, `ghostty`, `yazi`, `bat` et `starship`.
La vérification des conflits, les sauvegardes et le déploiement portent sur
les paquets sélectionnés. La préparation limite aussi les outils aux paquets
choisis, en plus de GNU Stow. Les plugins Zsh sont préparés lorsque `zsh` est
sélectionné. Avec `--status`, la sélection filtre les fichiers de configuration
affichés et le bilan des outils reste global.

### Sauvegardes et activation des réglages

Le déploiement place les fichiers remplacés dans un dossier privé
`~/.mac-setup-backup.XXXXXXXX`, dont le chemin est affiché, puis vérifie les
liens. Si une étape échoue, le script tente de restaurer les fichiers déplacés
et signale les conflits qui demandent une intervention manuelle. Conserver
le clone à son emplacement pour que les liens restent utilisables.

Le bilan de `--apply` indique l’étape atteinte, l’état du clone et les outils
et plugins disponibles, y compris après un échec partiel. Si Stow a créé
un dossier de sauvegarde, son bilan rappelle le chemin et liste les fichiers
restaurés en cas d’échec. En cas de conflit, le diagnostic de l’étape indique le
chemin concerné.

Après un arrêt brutal, vérifier les sauvegardes et les liens avant de retirer
le dossier de verrou vide `~/.mac-setup-stow.lock`. Le retirer seulement si
aucun déploiement n’est en cours.

La configuration de Ghostty est liée dans `~/.config/ghostty/`. Ghostty peut
aussi lire un fichier dans `~/Library/Application Support/com.mitchellh.ghostty/`
et donner la priorité à ses réglages. Le diagnostic signale ces fichiers.
Après application, ouvrir une nouvelle fenêtre Ghostty pour charger Zsh et
recharger les réglages de Ghostty au besoin. [Documentation Ghostty](https://ghostty.org/docs/config#file-location)

### Mettre à jour Mac_dotfiles

Pour comparer le clone avec la branche distante qu’il suit, utiliser la
simulation, puis appliquer la mise à jour si le bilan te convient :

```bash
bash scripts/zsh-setup.sh --update-dotfiles --dry-run
bash scripts/zsh-setup.sh --update-dotfiles --apply
```

La simulation consulte la branche distante. Si la nouvelle révision manque
dans le clone, Git en vérifiera l’historique après la récupération. Le script
s’arrête si le clone contient des changements locaux, s’il est sur une branche
sans suivi ou si une avance rapide est impossible. La révision locale de
départ est affichée et ses fichiers suivis sont archivés dans un dossier privé
`~/.mac-setup-dotfiles.*` avant la mise à jour. Le chemin exact est affiché.

La commande s’applique au clone entier. Les liens Stow existants reflètent les
changements des fichiers qu’ils pointent. Pour examiner les liens après une
mise à jour, lancer `bash scripts/zsh-setup.sh --dry-run`.

### Retour arrière

Ouvrir `liens.tsv` dans le dossier de sauvegarde affiché. Chaque ligne indique
l’état initial, la destination et le fichier source dans Mac_dotfiles.

1. Conserver les entrées marquées `conserve`.
2. Pour chaque entrée `nouveau` ou `sauvegarde`, vérifier avec `ls -l` que la
   destination est toujours un lien vers la source indiquée. Retirer ce lien
   avec `unlink` une fois vérifié. Si la destination est un fichier ordinaire
   ou pointe ailleurs, arrêter la restauration de cette entrée.
3. Pour une entrée `sauvegarde`, remettre le fichier sous `fichiers/` à sa
   destination d’origine. Par exemple, `fichiers/.config/bat/config` retourne
   dans `~/.config/bat/config`.

Pour un déploiement effectué avec l’ancienne version, conserver les journaux
`.deployments/` de Mac_dotfiles et les sauvegardes d’origine. Le nouveau
déploiement utilise sa propre liste de liens.

L’annulation des liens est indépendante des formules et des plugins installés.
