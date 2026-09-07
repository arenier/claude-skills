# claude-skills

Mes skills [Claude Code](https://claude.com/claude-code) — des procédures que je
répète assez souvent pour vouloir qu'elles soient exactes à chaque fois plutôt
que reconstruites de mémoire.

Un skill est un dossier contenant un `SKILL.md` : Claude Code le charge quand la
demande correspond à sa description. Il peut embarquer des scripts, que Claude
exécute au lieu de réinventer les commandes.

Ce repo sert de deux façons : les skills de déploiement GCP s'installent par lien
symbolique (ci-dessous), et le reste est distribué comme **marketplace de plugins**
Claude Code (voir [Marketplace `adri-skills`](#marketplace-adri-skills)).

## Installation des skills de déploiement

```bash
git clone https://github.com/arenier/claude-skills.git
for s in claude-skills/*/SKILL.md; do d="$(dirname "$s")"; ln -s "$PWD/$d" ~/.claude/skills/"$(basename "$d")"; done
```

Un lien symbolique plutôt qu'une copie : les modifications faites dans le repo
sont prises en compte immédiatement, sans resynchronisation. Le glob ne prend que
les dossiers portant un `SKILL.md` à leur racine — il ignore donc le plugin, dont
les skills vivent sous `adri-plugin/skills/`.

## Marketplace `adri-skills`

Le repo est aussi une [marketplace de plugins Claude Code](https://code.claude.com/docs/en/plugin-marketplaces),
déclarée dans [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).
Elle publie un plugin, **`adri-plugin`**, qui regroupe les skills du cycle de vie
d'une pull request.

Ajouter la marketplace et installer le plugin, en interactif :

```
/plugin marketplace add arenier/claude-skills
/plugin install adri-plugin@adri-skills
```

Ou le référencer dans le `.claude/settings.json` d'un projet, pour que le plugin
soit disponible à tout le monde sans installation manuelle :

```json
{
  "extraKnownMarketplaces": {
    "adri-skills": {
      "source": { "source": "github", "repo": "arenier/claude-skills" }
    }
  },
  "enabledPlugins": {
    "adri-plugin@adri-skills": true
  }
}
```

### Plugin `adri-plugin`

Trois skills qui couvrent la vie d'une PR, de l'ouverture à la réponse aux
retours. Écrits pour [pick-a-book](https://github.com/arenier/pick-a-book) :
`pr-review` et `pr-review-triage` confrontent le diff aux ADR et conventions de ce
repo, `create-pr` en applique les conventions de branche et de PR.

| Skill | Rôle |
|---|---|
| `create-pr` | Ouvre une PR décrite — branche, commits, push, puis corps orienté relecture (contexte, modifications, tests, ADR, points d'attention). |
| `pr-review` | Relit une PR en la confrontant aux ADR et conventions ; produit une fiche de review et un commentaire prêt à coller. Consultatif : ne merge ni ne pousse. |
| `pr-review-triage` | Traite une review déjà postée : vérifie chaque point contre le code, attribue un double verdict, applique les correctifs retenus avec test de non-régression, répond en commentaire. |

## `grill-me` / `grilling`

Interview relentless pour éprouver un plan ou une décision, avant de coder. Importé
depuis [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/grill-me)
(MIT) plutôt que référencé via sa marketplace : celle-ci ne publie qu'un plugin
unique regroupant tous les skills du repo source, sans moyen d'en installer un
seul isolément.

`grill-me` est le point d'entrée explicite (`disable-model-invocation`, ne se
déclenche jamais tout seul) ; il délègue à `grilling`, qui porte le vrai
comportement et peut aussi se déclencher de lui-même sur les tournures « grill »
(« grille-moi ce plan », etc.).

## Skills de déploiement

### `deploy-actual-gcp`

Déploie une instance vierge d'[Actual Budget](https://actualbudget.org/) dans son
propre projet GCP : création du projet, facturation, bucket Cloud Storage durci,
service account dédié, service Cloud Run et alerte budget.

Écrit pour héberger un budget par personne de la famille, dans un projet séparé
chacun. Le script est idempotent, donc il sert aussi de procédure de mise à jour
mensuelle.

Ce qu'il encode et qui ne se devine pas :

* **La propagation IAM.** Un service account tout juste créé n'est pas utilisable
  tout de suite, et deux sous-systèmes rattrapent leur retard à des vitesses
  différentes — les bindings IAM, puis le serveur de métadonnées qui émet les
  jetons. Le second échoue en `500` sur le montage gcsfuse, ce qui ressemble à
  une erreur de permission alors que c'est une course. Le script réessaie les
  deux.
* **`--max-instances=1`**, non négociable : SQLite sur gcsfuse ne supporte pas
  deux écrivains concurrents.
* **Un service account dédié**, sans quoi le service tourne sous le compte
  Compute par défaut et son `roles/editor` sur tout le projet.
* **Les trusted proxies d'Actual**, sans lesquels le rate limiting range tous les
  clients dans le même seau et les utilisateurs légitimes récoltent les 429 des
  autres.

Il s'appuie sur le travail de [daniefdz/actual-run](https://github.com/daniefdz/actual-run),
dont il reprend l'approche ; les corrections de propagation IAM ont été
reversées en amont.

### `backup-actual-gcp`

Sauvegarde quotidienne d'une instance Actual vers un bucket d'un projet dédié,
par Cloud Run Job et Cloud Scheduler.

La sauvegarde est **physique** — une copie du bucket — et non un export via
l'API d'Actual. C'est un choix, pas un raccourci : l'export logique réclame le
mot de passe du serveur, qui appartient à la personne pour qui tu héberges. La
copie de bucket n'utilise que l'accès GCP que tu as déjà.

Ce qu'il encode :

* **Aucun droit de suppression, nulle part.** Le service account lit la source
  et écrit la destination, sans jamais pouvoir effacer. Le versioning transforme
  les écrasements en archivage. Une compromission du job ne détruit pas
  l'historique.
* **`bucketViewer` en plus de `objectViewer`** sur les deux buckets : `rsync`
  lit les métadonnées du bucket avant de lister, et `objectViewer` ne porte pas
  `storage.buckets.get`.
* **Les jobs vivent dans le projet de sauvegarde**, jamais dans les projets
  sources — qui n'ont donc aucune prise sur leurs propres copies.

### `deploy-freshrss-gcp`

Déploie [FreshRSS](https://freshrss.org/) sur Cloud Run, données sur un bucket
monté en gcsfuse, flux actualisés par Cloud Scheduler.

Ce qu'il encode et qui ne se devine pas :

* **Le cron intégré ne sert à rien.** `CRON_MIN` installe un crontab *dans le
  conteneur* : il ne se déclenche que si le conteneur est éveillé, ce qui
  n'arrive jamais en `min-instances=0`. L'actualisation vient donc de
  l'extérieur, par un job planifié.
* **Le jeton d'actualisation ne passe pas dans l'URL du planificateur.** Une
  cible Cloud Scheduler est lisible avec un simple rôle de lecture et finit dans
  les journaux à chaque exécution — et ce jeton ne se contente pas de déclencher
  une actualisation : il donne aussi accès à la sortie RSS et à l'export OPML.
  Il reste dans Secret Manager, lu à l'exécution.
* **L'installation se fait depuis la spec**, par `FRESHRSS_INSTALL` et
  `FRESHRSS_USER`. Une instance publique et non installée laisse n'importe quel
  visiteur dérouler l'installateur web et s'approprier l'instance ; installer au
  premier démarrage ferme la fenêtre avant le premier octet de trafic.
* **Les secrets ne sont pas dans la spec.** Les variables y contiennent les
  chaînes littérales `$ADMIN_PASSWORD` et `$REFRESH_TOKEN` ; l'entrypoint les
  développe dans le conteneur à partir de ce que Secret Manager y injecte. En
  contrepartie les valeurs doivent rester alphanumériques : elles traversent un
  `eval`.
* **`--max-instances=1`**, pour la même raison que sur Actual : FreshRSS utilise
  SQLite, et SQLite sur gcsfuse ne supporte pas deux écrivains concurrents.
* **`base_url` doit être connue avant le premier démarrage**, puisque FreshRSS
  la fige à l'installation. L'URL Cloud Run en numéro de projet est
  déterministe, donc calculable d'avance.

## Licence

MIT
