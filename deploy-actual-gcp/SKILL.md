---
name: deploy-actual-gcp
description: Déployer une nouvelle instance vierge d'Actual Budget dans son propre projet GCP (Cloud Run + bucket gcsfuse), pour un proche. À utiliser quand on demande un nouveau serveur Actual, une instance Actual pour quelqu'un, ou un nouveau projet GCP Actual Budget.
---

# Nouvelle instance Actual Budget sur GCP

`deploy.sh` fait tout le déploiement. Ce document sert à choisir les entrées et à
comprendre ce qui peut mal tourner.

## Avant de lancer

1. **Vérifier l'authentification** : `gcloud auth list`. Si rien n'est actif,
   demander à l'utilisateur de lancer `! gcloud auth login` lui-même (interactif).
2. **Choisir le project ID**. Convention : `services-<prénom>-<initiale du nom>`,
   en minuscules, sans accent — `services-camille-b`. Un projet par bénéficiaire,
   pas d'organisation. Si le prénom n'est pas évident dans la demande, le demander.
3. **Vérifier qu'il est libre** : `gcloud projects describe <id>`. Les IDs sont
   globalement uniques et jamais réutilisables, y compris après suppression.

## Lancer

```bash
~/.claude/skills/deploy-actual-gcp/deploy.sh services-prenom-x
```

Overrides par variable d'environnement :

| Variable | Défaut | |
|---|---|---|
| `REGION` | `europe-west9` | Paris |
| `SERVER_VERSION` | dernière release GitHub | épingler pour reproduire un déploiement |
| `BUDGET_AMOUNT` | `5` | euros/mois, alerte scopée au projet |
| `BILLING_ACCOUNT` | premier compte ouvert | à fixer si tu en as plusieurs |

Le script est idempotent : le relancer met à jour le service sans recréer le
bucket, le service account ni le budget. C'est aussi la procédure de mise à jour
(`SERVER_VERSION=26.8.0 ./deploy.sh services-prenom-x`).

## Ce qu'il crée

```
Projet GCP dédié
├─ Cloud Run  actual-server        (public, max-instances=1, gen2)
│    └─ tourne comme actual-server-sa
├─ Bucket     actual-server-xxxxxxxx  monté sur /data  (UBLA + PAP)
│    └─ actual-server-sa : objectAdmin sur ce bucket uniquement
└─ Alerte budget à BUDGET_AMOUNT €/mois
```

Choix à ne pas défaire :

- **`--max-instances=1`** — SQLite sur gcsfuse ne supporte pas deux écrivains.
- **`--service-account`** explicite — sinon le service hérite du SA Compute par
  défaut, qui porte `roles/editor` sur tout le projet.
- **`ACTUAL_TRUSTED_PROXIES`** incluant `169.254.0.0/16`, le hop link-local de
  Cloud Run. Sans lui, Express refuse de lire `X-Forwarded-For` et
  express-rate-limit met tous les clients dans le même seau : les utilisateurs
  légitimes se prennent les 429 des autres. Express lit `X-Forwarded-For` de
  droite à gauche, donc ne faire confiance qu'à un seul hop n'est pas spoofable.
- **`ACTUAL_TRUSTED_AUTH_PROXIES=::1/128`** — hérite de `TRUSTED_PROXIES` s'il
  n'est pas fixé, et il active l'authentification par en-tête HTTP.

## Après

Donner l'URL au bénéficiaire et lui dire de **créer son compte tout de suite** :
le service est en `--allow-unauthenticated`, donc tant qu'aucun compte n'existe,
n'importe qui atteignant l'URL peut créer le premier.

Le service est joignable publiquement. Google absorbe les DDoS volumétriques en
amont, mais rien ne filtre le trafic applicatif : c'est l'alerte budget et
`max-instances=1` qui bornent la facture. Un vrai filtrage demanderait un load
balancer HTTPS externe + Cloud Armor, dont le coût fixe dépasse largement le
reste.

## Si ça échoue

**`cannot fetch token: ... Received 500`** dans les logs, et le conteneur ne
démarre pas : c'est la propagation IAM, pas une permission manquante (un vrai
refus donnerait 403). Le script réessaie trois fois à 60 s d'intervalle. Si les
trois passent, attendre quelques minutes et relancer — une révision qui ne
démarre pas ne reçoit aucun trafic, donc relancer est sans risque.

**`Service account ... does not exist`** juste après sa création : même cause,
le script boucle déjà jusqu'à 2 minutes dessus.

**L'alerte budget échoue** : `billingbudgets.googleapis.com` vient d'être activée
et met un moment à répondre. Le déploiement, lui, a réussi — relancer le script
plus tard suffit à créer l'alerte.

## À savoir

- Les quotas gratuits Cloud Run et Cloud Storage se comptent **par compte de
  facturation**, pas par projet : ils sont partagés avec tout le reste.
- L'alerte créée ici est scopée au projet : elle sert à savoir *lequel* dérape.
  Une alerte au niveau du compte de facturation, en filet global, est un bon
  complément — elle se crée une fois pour toutes, hors de ce script.
- Les mises à jour d'Actual sortent mensuellement et ne sont pas automatiques.
