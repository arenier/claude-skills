---
name: deploy-actual-gcp
description: Déployer une nouvelle instance vierge d'Actual Budget dans son propre projet GCP (Cloud Run + bucket gcsfuse), pour un proche. À utiliser quand on demande un nouveau serveur Actual, une instance Actual pour quelqu'un, ou un nouveau projet GCP Actual Budget.
---

# Nouvelle instance Actual Budget sur GCP

Tout ce qui est déterministe est dans un script : le vérifier avant, déployer, contrôler après. Ce
document dit quand lancer chacun, et comment trancher ce que les scripts ne peuvent pas décider.

## Déroulé

| # | Étape | Qui |
|---|---|---|
| 1 | Choisir le project ID | jugement |
| 2 | Vérifier les prérequis | script `preflight.sh` |
| 3 | Lever ce qui bloque, choisir le compte de facturation | jugement |
| 4 | Déployer | script `deploy.sh` |
| 5 | Diagnostiquer un échec | jugement (grille ci-dessous) |
| 6 | Contrôler l'instance | script `verify.sh` |
| 7 | Passer la main au bénéficiaire | jugement |

## 1. Choisir le project ID

Convention : `services-<prénom>-<initiale du nom>`, en minuscules, sans accent — `services-camille-b`.
Un projet par bénéficiaire, pas d'organisation. Si le prénom ou l'initiale ne ressort pas clairement
de la demande, le demander plutôt que de le deviner : l'ID est définitif.

## 2. Vérifier les prérequis

```bash
${CLAUDE_SKILL_DIR}/preflight.sh services-prenom-x
```

Une ligne par contrôle (`OK`, `KO` bloquant, `!!` à regarder), puis `PREFLIGHT=ok|blocked`.

## 3. Lever ce qui bloque

- **Aucun compte actif** → demander à l'utilisateur de lancer `! gcloud auth login` lui-même : c'est
  interactif, tu ne peux pas le faire à sa place.
- **ID invalide** → revenir à l'étape 1.
- **Projet existant** → `deploy.sh` fera une mise à jour, pas une création. Si ce n'était pas
  l'intention (homonyme, autre bénéficiaire), s'arrêter et le dire.
- **Projet introuvable** → il sera créé. Les IDs sont globalement uniques et jamais réutilisables,
  y compris après suppression : si un tiers le possède, la création échouera, et il faut un autre ID.
- **Plusieurs comptes de facturation** → demander lequel, puis le passer en `BILLING_ACCOUNT`. Le
  script prendrait sinon le premier, qui n'est pas forcément le bon.

## 4. Déployer

```bash
${CLAUDE_SKILL_DIR}/deploy.sh services-prenom-x
```

| Variable | Défaut | |
|---|---|---|
| `REGION` | `europe-west9` | Paris |
| `SERVER_VERSION` | dernière release GitHub | épingler pour reproduire un déploiement |
| `BUDGET_AMOUNT` | `5` | euros/mois, alerte scopée au projet |
| `BILLING_ACCOUNT` | premier compte ouvert | à fixer si tu en as plusieurs |

Le script est idempotent : le relancer met à jour le service sans recréer le bucket, le service
account ni le budget. C'est aussi la procédure de mise à jour mensuelle
(`SERVER_VERSION=26.8.0 ${CLAUDE_SKILL_DIR}/deploy.sh services-prenom-x`).

Ce qu'il crée :

```
Projet GCP dédié
├─ Cloud Run  actual-server        (public, max-instances=1, gen2)
│    └─ tourne comme actual-server-sa
├─ Bucket     actual-server-xxxxxxxx  monté sur /data  (UBLA + PAP)
│    └─ actual-server-sa : objectAdmin sur ce bucket uniquement
└─ Alerte budget à BUDGET_AMOUNT €/mois
```

## 5. Diagnostiquer un échec

Le script réessaie déjà ce qui relève de la propagation IAM. Ce qui remonte malgré tout se lit ainsi :

| Symptôme | Cause | Action |
|---|---|---|
| `cannot fetch token: ... Received 500` dans les logs, le conteneur ne démarre pas | propagation IAM (un vrai refus donnerait 403) | attendre quelques minutes et relancer : une révision qui ne démarre pas ne reçoit aucun trafic, relancer est sans risque |
| `Service account ... does not exist` juste après sa création | propagation IAM | le script boucle déjà 2 minutes dessus ; relancer |
| L'alerte budget échoue | `billingbudgets.googleapis.com` vient d'être activée | le déploiement a réussi ; relancer plus tard crée l'alerte |

Un symptôme hors de cette table : lire les logs
(`gcloud run services logs read actual-server --project=<id> --region=<région>`) avant de proposer
quoi que ce soit.

## 6. Contrôler l'instance

```bash
${CLAUDE_SKILL_DIR}/verify.sh services-prenom-x
```

Vérifie que le service répond, que les choix à ne pas défaire sont toujours en place (voir plus bas),
que la dernière révision a bien démarré, et si le premier compte a été créé. Sort en erreur sur tout
`KO`. À relancer aussi après chaque mise à jour.

## 7. Passer la main

Donner l'URL au bénéficiaire. Si `verify.sh` signale `no account yet`, lui dire de **créer son compte
tout de suite** : le service est en `--allow-unauthenticated`, donc tant qu'aucun compte n'existe,
n'importe qui atteignant l'URL peut créer le premier. Relancer `verify.sh` ensuite confirme que c'est
fait.

## Choix à ne pas défaire

`verify.sh` contrôle chacun d'eux ; si une demande revient à en défaire un, s'arrêter et expliquer.

- **`--max-instances=1`** — SQLite sur gcsfuse ne supporte pas deux écrivains.
- **`--service-account`** explicite — sinon le service hérite du SA Compute par défaut, qui porte
  `roles/editor` sur tout le projet.
- **`ACTUAL_TRUSTED_PROXIES`** incluant `169.254.0.0/16`, le hop link-local de Cloud Run. Sans lui,
  Express refuse de lire `X-Forwarded-For` et express-rate-limit met tous les clients dans le même
  seau : les utilisateurs légitimes se prennent les 429 des autres. Express lit `X-Forwarded-For` de
  droite à gauche, donc ne faire confiance qu'à un seul hop n'est pas spoofable.
- **`ACTUAL_TRUSTED_AUTH_PROXIES=::1/128`** — hérite de `TRUSTED_PROXIES` s'il n'est pas fixé, et il
  active l'authentification par en-tête HTTP.

## À savoir

- Le service est joignable publiquement. Google absorbe les DDoS volumétriques en amont, mais rien ne
  filtre le trafic applicatif : c'est l'alerte budget et `max-instances=1` qui bornent la facture. Un
  vrai filtrage demanderait un load balancer HTTPS externe + Cloud Armor, dont le coût fixe dépasse
  largement le reste.
- Les quotas gratuits Cloud Run et Cloud Storage se comptent **par compte de facturation**, pas par
  projet : ils sont partagés avec tout le reste.
- L'alerte créée ici est scopée au projet : elle sert à savoir *lequel* dérape. Une alerte au niveau
  du compte de facturation, en filet global, est un bon complément — elle se crée une fois pour
  toutes, hors de ce script.
- Les mises à jour d'Actual sortent mensuellement et ne sont pas automatiques.
