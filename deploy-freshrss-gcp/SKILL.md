---
name: deploy-freshrss-gcp
description: Déployer une instance FreshRSS auto-hébergée sur GCP (Cloud Run + bucket gcsfuse + actualisation par Cloud Scheduler). À utiliser quand on demande un lecteur RSS auto-hébergé, un serveur FreshRSS, ou le déploiement de FreshRSS sur Cloud Run.
---

# FreshRSS sur Cloud Run

Tout ce qui est déterministe est dans un script : le vérifier avant, déployer, contrôler après. Ce
document dit quand lancer chacun, et comment trancher ce que les scripts ne peuvent pas décider.

## Déroulé

| # | Étape | Qui |
|---|---|---|
| 1 | Choisir le projet | jugement |
| 2 | Vérifier les prérequis | script `preflight.sh` |
| 3 | Lever ce qui bloque, choisir le compte de facturation | jugement |
| 4 | Déployer | script `deploy.sh` |
| 5 | Diagnostiquer un échec | jugement (grille ci-dessous) |
| 6 | Contrôler l'instance et une actualisation réelle | script `verify.sh` |
| 7 | Passer la main | jugement |

## 1. Choisir le projet

FreshRSS n'a pas besoin d'un projet dédié : contrairement à un budget partagé, une instance sert en
général une seule personne, celle qui administre. La déposer dans le projet qui porte déjà ses
services est légitime. Demander lequel si ce n'est pas dit.

## 2. Vérifier les prérequis

```bash
${CLAUDE_SKILL_DIR}/preflight.sh <projet>
```

Une ligne par contrôle (`OK`, `KO` bloquant, `!!` à regarder), puis `PREFLIGHT=ok|blocked`.

## 3. Lever ce qui bloque

- **Aucun compte actif** → demander à l'utilisateur de lancer `! gcloud auth login` lui-même
  (interactif).
- **Projet introuvable** → le script le créera. Les IDs sont globalement uniques et jamais
  réutilisables, y compris après suppression : si un tiers le possède, la création échouera.
- **Projet qui porte déjà d'autres services** → c'est le cas prévu ; le signaler simplement.
- **FreshRSS déjà déployé** → le lancement sera une mise à jour, pas une création.
- **Plusieurs comptes de facturation** → demander lequel, puis le passer en `BILLING_ACCOUNT`.

## 4. Déployer

```bash
${CLAUDE_SKILL_DIR}/deploy.sh <projet>
```

| Variable | Défaut | |
|---|---|---|
| `REGION` | `europe-west9` | Paris |
| `FRESHRSS_VERSION` | dernière release GitHub | épingler pour reproduire un déploiement |
| `ADMIN_USER` | `admin` | sans espace : l'argument est découpé sur les blancs |
| `LANGUAGE` | `fr` | |
| `TIMEZONE` | `Europe/Paris` | sert au conteneur *et* au planificateur |
| `REFRESH_SCHEDULE` | `0 * * * *` | actualisation horaire |
| `BUDGET_AMOUNT` | `5` | euros/mois, alerte scopée au projet |
| `BILLING_ACCOUNT` | premier compte ouvert | à fixer si tu en as plusieurs |

Le script est idempotent : le relancer met à jour le service sans recréer le bucket, les service
accounts, les secrets ni le budget. C'est aussi la procédure de mise à jour
(`FRESHRSS_VERSION=1.29.0 ${CLAUDE_SKILL_DIR}/deploy.sh <projet>`).

Ce qu'il crée :

```
Projet GCP
├─ Cloud Run  freshrss              (public, max-instances=1, gen2, port 80)
│    └─ tourne comme freshrss-sa
├─ Bucket     freshrss-xxxxxxxx     monté sur /var/www/FreshRSS/data
│    │                              (UBLA + PAP + versioning)
│    └─ freshrss-sa : objectAdmin sur ce bucket uniquement
├─ Secrets    freshrss-admin-password, freshrss-refresh-token
├─ Cloud Run Job  freshrss-refresh  + Cloud Scheduler horaire
│    └─ tourne comme freshrss-refresh-sa
└─ Alerte budget à BUDGET_AMOUNT €/mois
```

## 5. Diagnostiquer un échec

Le script réessaie déjà ce qui relève de la propagation IAM. Ce qui remonte malgré tout se lit ainsi :

| Symptôme | Cause | Action |
|---|---|---|
| `cannot fetch token: ... Received 500` dans les logs, le conteneur ne démarre pas | propagation IAM (un vrai refus donnerait 403) | attendre quelques minutes et relancer : une révision qui ne démarre pas ne reçoit aucun trafic, relancer est sans risque |
| `Service account ... does not exist` juste après sa création | propagation IAM | le script boucle déjà 2 minutes dessus ; relancer |
| `Revision template should contain exactly one container with an exposed port` | `PORT` passé en variable d'environnement | le retirer : variable réservée par Cloud Run (voir `--port=80` plus bas) |
| Démarrage à froid anormalement long | `chown -R`/`chmod -R` de l'entrypoint sur gcsfuse | voir « Démarrage à froid » plus bas |
| L'alerte budget échoue | `billingbudgets.googleapis.com` vient d'être activée | le déploiement a réussi ; relancer plus tard |

**Démarrage à froid.** `entrypoint.sh` lance `cli/access-permissions.sh` à chaque démarrage, soit
`chown -R` et `chmod -R` sur le répertoire de données — donc sur gcsfuse. Les changements de
propriétaire n'y sont pas supportés et le parcours récursif est lent. Le script est tolérant (chaque
commande retombe sur un avertissement), donc l'instance démarre quand même, mais le coût grandit avec
`cache/` et `favicons/`. Si ça devient gênant : `mount-options=uid=33,gid=33` sur le volume
(33 = `www-data` sur Debian), ou sortir le cache du bucket.

## 6. Contrôler l'instance

```bash
${CLAUDE_SKILL_DIR}/verify.sh <projet>                # --no-refresh pour sauter l'actualisation réelle
```

Vérifie les choix à ne pas défaire (voir plus bas), l'absence de secret dans la spec, que `/api/`
répond 200, que le planificateur est actif, puis lance une actualisation de bout en bout. Sort en
erreur sur tout `KO`.

Un job d'actualisation en échec alors que le service répond signifie presque toujours que le jeton et
l'utilisateur ne correspondent pas — l'action `actualize` renvoie alors une erreur d'authentification,
pas un 500.

## 7. Passer la main

Donner l'URL et l'identifiant (`ADMIN_USER`). Le mot de passe a été généré et n'a jamais été
affiché ; l'utilisateur le lit lui-même, tu n'as pas à le recopier dans la conversation :

```bash
gcloud secrets versions access latest --secret=freshrss-admin-password --project=<projet>
```

Pour un client mobile (Fever / Google Reader), le mot de passe d'API est distinct et se fixe depuis
le profil dans l'interface.

## Choix à ne pas défaire

`verify.sh` contrôle chacun d'eux ; si une demande revient à en défaire un, s'arrêter et expliquer.

- **`--max-instances=1`** — FreshRSS utilise SQLite, et SQLite sur gcsfuse ne
  supporte pas deux écrivains concurrents. Même contrainte que pour Actual.
- **`--execution-environment=gen2`** — requis pour les montages Cloud Storage.
- **`--port=80`** — l'image Debian officielle a `Listen 80` en dur dans sa
  configuration Apache. Ne **pas** passer `PORT` en variable d'environnement :
  c'est une variable réservée par Cloud Run, et le déploiement échoue sur
  `Revision template should contain exactly one container with an exposed port`
  sans jamais nommer `PORT`. La variable `LISTEN` de l'image existe, mais elle
  ne sert à rien ici.
- **`--service-account` explicite** — sinon le service hérite du compte Compute
  par défaut. Aucun rôle n'est accordé au niveau du projet : `objectAdmin` sur
  le seul bucket, `secretAccessor` sur les seuls secrets.
- **`TRUSTED_PROXY=169.254.0.0/16 …`** — le hop link-local de Cloud Run.
  L'entrypoint pousse cette valeur dans `RemoteIPInternalProxy` d'Apache **et**
  elle écrase `trusted_sources` côté PHP (`app/Utils/httpUtil.php`). Sans elle,
  FreshRSS journalise l'adresse du proxy Google au lieu de celle du client.
  La liste est séparée par des blancs — les deux consommateurs découpent dessus.

  ⚠️ **Différence avec Actual.** Actual sépare `TRUSTED_PROXIES` (rate limiting)
  et `TRUSTED_AUTH_PROXIES` (authentification par en-tête). FreshRSS n'a
  **qu'une** liste, qui sert aux deux. C'est sans conséquence en
  `auth_type=form`, le défaut posé ici ; ça en aurait en `http_auth`, où faire
  confiance à un hop reviendrait à accepter un en-tête `REMOTE_USER` de sa part.

## L'installation sans fenêtre d'exposition

`FRESHRSS_INSTALL` et `FRESHRSS_USER` sont des listes d'arguments pour
`cli/do-install.php` et `cli/create-user.php`, rejouées par l'entrypoint à chaque
démarrage — et sans effet une fois l'instance installée (code de sortie 3).

Ça vaut mieux qu'un confort. Une instance FreshRSS publique et non installée
laisse **n'importe quel visiteur dérouler l'installateur web** et s'approprier
l'instance. Installer depuis la spec ferme la fenêtre avant le premier octet de
trafic. (La recette Actual, elle, laisse cette course ouverte : d'où la consigne
d'y créer le compte immédiatement. Ici, il n'y a rien à courir.)

`base_url` doit être connue **avant** le premier démarrage, puisque FreshRSS la
fige dans `config.php` à l'installation. L'URL Cloud Run en numéro de projet est
déterministe (`https://<service>-<numéro>.<région>.run.app`), donc calculable
avant le déploiement.

## Où vivent les secrets

Le mot de passe admin et le jeton d'actualisation sont générés une fois, jamais
affichés, et ne vivent que dans Secret Manager. Le relancement du script ne les
régénère pas — sinon il te verrouillerait dehors.

Ils n'apparaissent pas dans la spec Cloud Run : `FRESHRSS_USER` y contient les
chaînes littérales `$ADMIN_PASSWORD` et `$REFRESH_TOKEN`, et l'entrypoint les
développe dans le conteneur (`eval "echo \"$FRESHRSS_USER\""`) à partir de ce que
Secret Manager y injecte.

⚠️ **Les deux valeurs doivent rester alphanumériques.** Elles traversent un
`eval` : une apostrophe ou un `$` casserait le démarrage du conteneur, ou pire,
s'exécuterait.

## L'actualisation des flux

**Le cron intégré de FreshRSS ne sert à rien ici.** `CRON_MIN` installe un vrai
crontab *dans le conteneur* : il ne se déclenche que si le conteneur est éveillé,
ce qui n'arrive jamais en `min-instances=0`. Le déclencheur doit venir de
l'extérieur, sur l'action `actualize` :

```
GET <base_url>/i/?c=feed&a=actualize&user=<user>&token=<jeton>
```

`app/Controllers/feedController.php` accepte cette action si l'actualisation
anonyme est autorisée **ou** si le jeton est valide. On prend le jeton :
`allow_anonymous_refresh` sur une URL publique laisserait n'importe qui
déclencher des requêtes sortantes depuis ton instance.

**Le jeton ne passe pas dans l'URL du planificateur, et c'est délibéré.** Une
cible Cloud Scheduler est lisible par quiconque a `cloudscheduler.viewer`, et
elle est écrite dans Cloud Logging à chaque exécution. Or ce jeton n'est pas un
simple bouton d'actualisation : `indexController.php` l'accepte aussi pour la
sortie RSS et pour l'export OPML, donc il donne accès en lecture aux articles et
à la liste des abonnements. Il reste dans Secret Manager, et un Cloud Run Job
minuscule le lit à l'exécution.

Cloud Scheduler est gratuit jusqu'à **3 jobs par compte de facturation**, pas par
projet. Au-delà, compter ~0,10 $/mois.

## Pas de sauvegarde

Volontaire, comme pour les services dont l'état est reconstituable. Le bucket
contient des abonnements (exportables en OPML) et des articles (re-téléchargeables).
Ce qu'une perte coûterait vraiment, c'est l'état lu/non-lu et les favoris. Le
versioning couvre l'écrasement, qui est le mode de défaillance réaliste.

Si l'historique de lecture prend de la valeur, le motif à reprendre est celui
d'une copie physique du bucket par Cloud Run Job — en gardant à l'esprit le
quota Cloud Scheduler.

## À savoir

- Les quotas gratuits Cloud Run et Cloud Storage se comptent **par compte de
  facturation**, pas par projet.
- L'API FreshRSS (Fever / Google Reader, pour les clients mobiles) est activée
  par `--api-enabled`.
- Le service est joignable publiquement, derrière le formulaire de connexion de
  FreshRSS. Google absorbe les DDoS volumétriques, mais rien ne filtre le trafic
  applicatif : ce sont l'alerte budget et `max-instances=1` qui bornent la
  facture.
