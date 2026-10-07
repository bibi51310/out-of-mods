# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/). Dates en AAAA-MM-JJ.

## Pay Dirt — 0.1.0 (2026-10-07) — première préversion publique

Testé sur Out of Ore 0.36.5550 (build Steam 25627989, branche bêta).

### Ajouté
- **Prix de vente x2** (facteur réglable) pour les ressources et les minerais, **prix affiché et argent reçu** identiques. Achats, quêtes et bourse inchangés ; engins, bâtiments, pièces et équipements non doublés (pas de boucle achat / revente).
- Commandes : `boost <facteur>`, `boost_status`, `boost_scope ore|all`, `boost_mode price|bonus`, `boost_log 0|1`.
- Aucune sauvegarde modifiée : le mod se charge sur une partie existante et se retire sans trace.

## FlatGround 2 — 0.2.0 (2026-10-06)

Testé sur Out of Ore 0.36.5550 (build Steam 25627989, branche bêta).

### Ajouté
- **Plancher en pente** : page « Pente » (Départ ici, Piquet A / B, pourcentage ±0,5 / ±1) ; le creusage est limité par le plan incliné.
- **Piquets 3D** et fil lumineux le long du plan (blanc = remblayer, rouge = creuser, vert = ok à ±10 cm), textes 3D de guidage.
- **La lame automatique suit la pente** (décalage de coupe de 165 cm pris en compte).
- **Panneau bilingue FR / EN** (langue du jeu détectée, bouton FR/EN, commande `flat2_lang`).
- Commandes : `flat2_slope`, `flat2_start`, `flat2_stakes`, `flat2_stake_a`, `flat2_stake_b`.

### Modifié
- « Départ ici » pose le plan au sol réel, à la position de la lame.

## Out of Mods — 0.1.1 (2026-10-06)

### Modifié
- Description des mods en anglais quand l'interface est en anglais ; zone de description à hauteur fixe.
- Icône (fenêtre, barre des tâches, exécutable) et bannière d'en-tête.

## FlatGround 2 — 0.1.0 (2026-10-04) — première préversion publique

Testé sur Out of Ore 0.36.5550 (build Steam 25627989, branche bêta).

### Ajouté
- Plancher de creusage Z (pelleteuses, chargeuses, bulldozers) : boîte de creusage raccourcie, sphères corrigées ; plancher mémorisé entre les parties.
- Panneau en jeu (F7 / F8) : déplaçable à la souris, taille réglable, **adapté à la résolution**, masqué pendant le menu du jeu, deux onglets (Plancher / Lame).
- Actions de plancher : *Dernier coup*, *= Tranchant*, *= Visé* (sol visé), *Désactiver*, réglage fin ±1 / ±10 cm.
- Hauteurs nommées (liste paginée, mise à jour, suppression).
- **Lame automatique de bulldozer** par l'AutoLevel natif du jeu : tient le tranchant au plancher (±1–2 cm), décalage ±1 / ±5 cm, **levée en marche arrière** réglable, **reprise automatique** après coupure du module sous résistance, inclinaison latérale gérée par le module. Bulldozer seulement ; J = arrêt d'urgence.
- Commandes de console : `flat2_lock`, `flat2_set`, `flat2_adj`, `flat2_off`, `flat2_status`, `flat2_scale`, `flat2_panel_reset`.
- Paquet autonome (API embarquée, `mod.json`, `enabled.txt`) : un seul dossier à copier.

### Notes
- La lame automatique demande le module AutoLevel monté sur le bulldozer (branche bêta).
- Plusieurs mods du projet (`FlatGround`, `FlatGround2`) peuvent coexister ; désactivez l'un des deux pour une comparaison stricte.

## Out of Mods — 0.1.0 (2026-10-04)

### Ajouté
- Détection (lecture seule) du jeu Steam (dossier, build, branche), d'UE4SS et des mods installés, avec avertissement de compatibilité (build testé ≠ build du jeu).
- Installation / désinstallation / activation de mods **avec fenêtre de confirmation détaillée** ; sauvegardes automatiques ; manifeste d'installation.
- Paquets validés strictement : un dossier racine, `mod.json` + `Scripts/main.lua`, **aucun exécutable** (liste blanche d'extensions), pas de chemins dangereux, 20 Mo max.
- **Installation d'UE4SS à la demande** (téléchargement HTTPS github.com à empreinte SHA-256 figée, ou depuis un fichier local), réglages recommandés pour Out of Ore sur un nouveau fichier de réglages, retrait avec **restauration** des fichiers remplacés. Validé en conditions réelles (installation « joueur neuf »).
- Lancement du jeu via Steam sur clic.
- **Interface en français et en anglais** : langue choisie automatiquement d'après Windows, sélecteur « Français / English » dans la fenêtre (choix mémorisé).
- **Mises à jour** (launcheur et mods) sur demande : manifeste `updates.json` + archives vérifiées par empreinte SHA-256, confirmation détaillée, sauvegarde de la version précédente ; vérification au démarrage **facultative** (désactivée par défaut).
- Thème moderne clair / sombre ; journal coloré avec fichier, rapport de diagnostic à copier.
- Aucun accès réseau hors téléchargement d'UE4SS ou recherche de mises à jour demandés.

## OutOfOreAPI — 0.1.0 (2026-10-04)

### Ajouté
- Plomberie : `Json`, `IPC`, `SafeTick`, `Hook`, `Console` (+ `Exec`), `Keybind`, `CallFunction`, `DataTable`, `Events`.
- Monde / engins / partie : `World`, `Terrain` (hauteur du sol, point visé), `Land`, `Vehicle`, `GPS`, `AutoLevel`, `Inventory`, `Player`, `Game`, `Settings`, `Market`.
- Interface : `UI.Window` (fenêtres natives déplaçables), `UI.Marker` (étiquettes ancrées au monde).
- Outils : `Debug.Inspect`, mod `EventSpy`, commande `api_selftest` (32 lectures de non-régression).
- Voir `api/README.md`.
