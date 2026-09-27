---
name: backup-actual-gcp
description: Sauvegarder une instance Actual Budget hébergée sur Cloud Run vers un bucket d'un projet GCP dédié, planifié quotidiennement. À utiliser quand on demande de sauvegarder Actual, de protéger les données d'un budget, d'ajouter une instance à la sauvegarde existante, ou de vérifier qu'une sauvegarde fonctionne.
---

# Sauvegarde d'une instance Actual Budget

Copie le bucket d'une instance Actual vers un bucket dédié dans un projet de sauvegarde central.
Complément de [[deploy-actual-gcp]].

## Déroulé

| # | Étape | Qui |
|---|---|---|
| 1 | Choisir le projet de sauvegarde (une fois) | jugement |
| 2 | Créer le projet central (une fois) | script `bootstrap.sh` |
| 3 | Ajouter une instance | script `add-instance.sh` |
| 4 | Vérifier que la sauvegarde est saine **et à jour** | script `verify.sh` |
| 5 | Interpréter un `KO` | jugement (grille ci-dessous) |

## 1. Choisir le projet de sauvegarde

Un seul projet central pour toutes les instances, distinct de chacune d'elles : les projets sources
n'ont ainsi aucune prise sur leurs propres copies. S'il existe déjà (une instance a déjà été ajoutée),
le réutiliser. Sinon, demander l'ID à l'utilisateur.

## 2. Créer le projet central

```bash
${CLAUDE_SKILL_DIR}/bootstrap.sh <backup-project-id>
```

## 3. Ajouter une instance

```bash
${CLAUDE_SKILL_DIR}/add-instance.sh <source-project> <backup-project>
```

Le bucket source est lu **sur le service Cloud Run lui-même**, donc la sauvegarde ne peut pas viser le
mauvais bucket. Le script est idempotent : le relancer met à jour le job et la planification sans rien
recréer — y compris pour changer la récurrence (`SCHEDULE='0 6 * * *' …/add-instance.sh …`).

| Variable | Défaut | |
|---|---|---|
| `SCHEDULE` | `0 3 * * *` | expression cron |
| `TIMEZONE` | `Europe/Paris` | |
| `REGION` | `europe-west9` | |
| `KEEP_DAYS` | `30` | rétention des versions remplacées |
| `KEEP_VERSIONS` | `3` | versions conservées quoi qu'il arrive |
| `SOURCE_BUCKET` | lu sur le service | à forcer si détection impossible |

Ce qu'il crée :

```
Projet de sauvegarde
├─ Bucket  actual-backup-<source-project>   (versioning, UBLA, PAP)
├─ SA      backup-<source-project>-sa
│     ├─ source : objectViewer + bucketViewer     (lecture seule)
│     └─ dest   : + objectAdmin                   (écraser exige delete)
├─ Job Cloud Run   actual-backup-<source-project>
└─ Job Scheduler   actual-backup-<source-project>-daily
```

Et, sur le bucket **source**, activation du versioning — protection immédiate contre l'écrasement,
indépendante de la copie.

Après un ajout, lancer une première copie
(`gcloud run jobs execute actual-backup-<source-project> --region=<région> --project=<backup-project> --wait`)
puis passer à l'étape 4 : ne pas attendre la nuit pour savoir si ça marche.

## 4. Vérifier

```bash
${CLAUDE_SKILL_DIR}/verify.sh <source-project> <backup-project>
```

Trois contrôles, une ligne `OK` / `KO` / `!!` chacun :

1. la dernière exécution du job a réussi, et il y a combien de temps ;
2. chaque objet source est dans la sauvegarde avec le même MD5 — un objet modifié **depuis la
   dernière copie réussie** peut légitimement différer (`!!`), toute autre différence est un `KO` ;
3. `PRAGMA integrity_check` sur les SQLite de la sauvegarde, si `sqlite3` est installé.

Le contrôle d'intégrité seul ne suffit pas, et c'est pour ça que le script fait les deux autres :
**une copie périmée est structurellement saine et répond `ok`**. C'est ce qui a masqué le bug
d'écrasement décrit plus bas pendant une journée.

## 5. Interpréter un `KO`

| Signal | Lecture probable | Premier geste |
|---|---|---|
| Dernière exécution en échec | un job en échec ne prévient personne | lire ses logs : `gcloud logging read 'resource.labels.job_name=actual-backup-<projet>' --project=<backup-project> --limit=30` |
| `does not have storage.buckets.get access` dans ces logs | `bucketViewer` manquant | relancer `add-instance.sh`, qui le pose |
| 403 sur les seuls fichiers déjà présents | droit de suppression manquant sur la destination | idem — voir « objectAdmin » plus bas |
| Objets absents ou différents alors qu'inchangés depuis la dernière copie réussie | la copie n'écrit pas ce qu'elle devrait | lire les logs de la dernière exécution avant toute autre hypothèse |
| Aucune exécution depuis plus de 2 jours | planification en pause ou supprimée | `gcloud scheduler jobs describe actual-backup-<projet>-daily --location=<région> --project=<backup-project>` |

## Le principe

La sauvegarde est **physique** : on recopie les fichiers du bucket, on ne passe pas par l'API
d'Actual.

Ça compte, parce que l'export logique (`@actual-app/api`, cf. les outils communautaires) exige le
**mot de passe du serveur** de chaque instance. Quand tu héberges pour quelqu'un d'autre, ce mot de
passe est le sien : le réclamer te donnerait un accès permanent à son interface, et beaucoup de gens
réemploient leurs mots de passe ailleurs. La copie de bucket n'utilise que l'accès GCP que tu as déjà
par construction. C'est la méthode la moins intrusive des deux, alors qu'elle en a l'air davantage.

Contrepartie assumée : on sauvegarde l'état du serveur, pas un ZIP réimportable ailleurs. Pour une
reprise après sinistre — projet supprimé, bucket effacé, corruption — c'est ce qu'il faut.

## Choix à ne pas défaire

- **Lecture seule sur la source.** Le job ne peut pas altérer le budget qu'il protège. Ça, c'est non
  négociable.
- **`objectAdmin` sur la destination, donc avec droit de suppression.** Contre l'intuition, et contre
  la première version de ce skill, qui n'accordait que `objectCreator` en pensant que le versioning
  suffisait à transformer un écrasement en archivage. C'est faux : **écraser un objet GCS existant
  exige `storage.objects.delete`**, versioning ou pas.

  Le mode de défaillance est vicieux. Le job copie sans problème les fichiers nouveaux, et échoue en
  403 sur chaque fichier déjà présent qui a changé. Un budget est donc sauvegardé une fois, puis
  jamais rafraîchi, pendant que le job échoue chaque nuit sans que personne ne regarde. Découvert le
  2 août 2026, un jour après la mise en place, sur une sauvegarde qui semblait valide.

  Ce que `objectCreator` protégeait est déjà assuré par le bucket : le versioning archive chaque
  écrasement, et le soft delete rend récupérable pendant sept jours même une purge délibérée des
  versions archivées.
- **`--checksums-only` sur le rsync.** La source est écrite par gcsfuse, qui pose son propre
  `gcsfuse_mtime` et non le `goog-reserved-file-mtime` que rsync lit. Comparer les dates revient donc
  à s'appuyer sur une métadonnée qui n'est pas fiablement là. Les hashes sont déjà dans les
  métadonnées GCS : aucun transfert supplémentaire.
- **`bucketViewer` en plus de `objectViewer`.** `rsync` lit les métadonnées du bucket avant de lister,
  et `objectViewer` ne porte pas `storage.buckets.get` — sans lui le job échoue sur
  `does not have storage.buckets.get access`. `bucketViewer` n'ajoute que `buckets.get` et
  `buckets.list`.
- **Pas de `--delete-unmatched-destination-objects`.** Un fichier disparu de la source reste dans la
  sauvegarde.
- **Les jobs vivent dans le projet de sauvegarde**, pas dans les projets sources. Ces derniers n'ont
  donc aucun droit sur les sauvegardes : compromettre une instance ne donne pas prise sur ses copies.
- **Pas de retention policy verrouillée.** Elle est irréversible, et le versioning plus le soft delete
  couvrent déjà la suppression accidentelle comme la malveillante sur sept jours. C'est le dernier
  filet à envisager si un jour ce raisonnement ne suffit plus — depuis que le SA peut supprimer, il
  n'est plus purement théorique.

## Cohérence des données

Le budget est un SQLite. Le copier pendant une écriture donnerait un fichier incohérent — sauf que
les instances déployées par [[deploy-actual-gcp]] sont en `min-instances=0` : après un quart d'heure
d'inactivité le conteneur s'arrête, gcsfuse vide ses tampons et referme les fichiers. Une copie
nocturne tombe donc sur une base fermée. Ce n'est pas une garantie absolue — quelqu'un peut saisir une
dépense à 3 h — mais le versioning conserve les copies précédentes, dont une saine.

## Coût

Cloud Scheduler est gratuit jusqu'à 3 jobs par compte de facturation. Le job Cloud Run ne tourne que
quelques secondes par nuit. Le stockage se compte en centimes. En pratique, la sauvegarde ne change
pas la facture.
