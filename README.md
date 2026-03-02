# Sécurité : exécuter un conteneur en non-root : solution

[⬅️ 05-troubleshooting](../../tree/05-troubleshooting) ·
[📋 Sommaire](../../tree/main) ·
[07-securite-secrets ➡️](../../tree/07-securite-secrets)

[📝 Retour à l'énoncé](../../tree/06-securite-non-root)

---

## Rappel de l'objectif

Observer qu'un conteneur s'exécute par défaut en `root`, créer un utilisateur non-root dans un Dockerfile, et utiliser l'utilisateur intégré des images `.NET 8+`.

## Solution

### Étape 1 — Observer qu'un conteneur s'exécute par défaut en `root`

#### Build et lancement

```bash
# Build root
docker build -t hello-nonroot:root -f Dockerfile.root .
# Run root
docker run -d -p 8080:8080 --name nonroot-test hello-nonroot:root
```

#### Vérification de l'utilisateur via l'API

```bash
curl -s http://localhost:8080 | jq
# {
#   "title": "Hello Sécurité !",
#   "user": "root",
#   "message": "Le endpoint / fonctionne correctement !"
# }
```

> Le champ `user` affiche `root` car `Environment.UserName` retourne le nom de l'utilisateur qui exécute le processus `.NET`. Par défaut, c'est `root`.

#### Vérification via `docker exec`

```bash
docker exec nonroot-test whoami
# root

docker exec nonroot-test id
# uid=0(root) gid=0(root) groups=0(root)
```

> L'UID `0` correspond à root sur les systèmes Linux. Le processus a donc un accès complet au système de fichiers du conteneur.

#### Vérification des permissions sur les fichiers

```bash
docker exec nonroot-test ls -la /app
# total 120
# -rwxr-xr-x 1 root root 72720 Mar  2 15:10 HelloNonRoot
# -rw-r--r-- 1 root root   406 Mar  2 15:10 HelloNonRoot.deps.json
# -rw-r--r-- 1 root root  7680 Mar  2 15:10 HelloNonRoot.dll
# -rw-r--r-- 1 root root 20436 Mar  2 15:10 HelloNonRoot.pdb
# -rw-r--r-- 1 root root   469 Mar  2 15:10 HelloNonRoot.runtimeconfig.json
# -rw-r--r-- 1 root root   488 Mar  2 15:10 web.config
```

> Tous les fichiers appartiennent à `root:root`. C'est le comportement par défaut de l'instruction `COPY` dans un Dockerfile.

### Étape 2 — Créer un utilisateur non-root

#### `Dockerfile.nonroot`

```dockerfile
# ---------- Stage 2 : Runtime ----------
...
# Créer un utilisateur "appuser" sans shell de login
# -r => pas de home directory
# -s /bin/false => connexion interractive impossible (su - appuser et ssh)
RUN useradd -r -s /bin/false appuser
...
# Copier les fichiers avec le bon propriétaire
# (les fichiers dans /app/publish ont appuser comme owner)
COPY --from=build --chown=appuser /app/publish .

# Spécifier l'utilisateur non-root comme user pour l'exécution
USER appuser

...
```

#### Build et lancement

```bash
# Build
docker build -t hello-nonroot:nonroot -f Dockerfile.nonroot .

docker run -d -p 8080:8080 --name nonroot-nonroot hello-nonroot:nonroot
```

#### Vérification de l'utilisateur via l'API

```bash
curl -s http://localhost:8080 | jq
# {
#   "title": "Hello Sécurité !",
#   "user": "appuser",
#   "message": "Le endpoint / fonctionne correctement !"
# }
```

#### Vérification via `docker exec`

```bash
docker exec nonroot-nonroot whoami
# appuser

docker exec nonroot-nonroot id
# uid=999(appuser) gid=999(appuser) groups=999(appuser)
```

> L'UID n'est plus `0`. Le processus n'a plus les privilèges root.

#### Vérification des permissions sur les fichiers

```bash
docker exec nonroot-nonroot ls -la /app
# total 120
# -rwxr-xr-x 1 appuser appuser 72720 Mar  2 15:10 HelloNonRoot
# -rw-r--r-- 1 appuser appuser   406 Mar  2 15:10 HelloNonRoot.deps.json
# -rw-r--r-- 1 appuser appuser  7680 Mar  2 15:10 HelloNonRoot.dll
# -rw-r--r-- 1 appuser appuser 20436 Mar  2 15:10 HelloNonRoot.pdb
# -rw-r--r-- 1 appuser appuser   469 Mar  2 15:10 HelloNonRoot.runtimeconfig.json
# -rw-r--r-- 1 appuser appuser   488 Mar  2 15:10 web.config
```

> Les fichiers de l'application appartiennent à `appuser` grâce à `COPY --chown`. Le répertoire `/app` lui-même appartient toujours à `root` (créé par `WORKDIR` avant le `USER`).

### Étape 3 — Utiliser l'utilisateur intégré .NET

#### `Dockerfile.dotnet` corrigé

```dockerfile
# ---------- Stage 2 : Runtime ----------
...
# Copier les fichiers avec le bon propriétaire
COPY --from=build --chown=app /app/publish .

# Utiliser l'utilisateur intégré .NET
USER app

...
```

> L'utilisateur `app` (UID `1654`) est pré-créé dans toutes les images `mcr.microsoft.com/dotnet/aspnet:8.0` et `mcr.microsoft.com/dotnet/sdk:8.0`. Il n'est pas nécessaire de le créer avec `RUN`, ce qui simplifie le Dockerfile et supprime un layer.

#### Build et lancement

```bash
docker build -t hello-nonroot:dotnet -f Dockerfile.dotnet .

docker run -d -p 8080:8080 --name nonroot-dotnet hello-nonroot:dotnet
```

#### Vérification de l'utilisateur via l'API

```bash
curl -s http://localhost:8080 | jq
# {
#   "title": "Hello Sécurité !",
#   "user": "app",
#   "message": "Le endpoint / fonctionne correctement !"
# }
```

#### Vérification via `docker exec`

```bash
docker exec nonroot-dotnet whoami
# app

docker exec nonroot-dotnet id
# uid=1654(app) gid=1654(app) groups=1654(app)
```

#### Vérification des permissions sur les fichiers

```bash
docker exec nonroot-dotnet ls -la /app
# total 120
# -rwxr-xr-x 1 app  app  72720 Mar  2 15:10 HelloNonRoot
# -rw-r--r-- 1 app  app    406 Mar  2 15:10 HelloNonRoot.deps.json
# -rw-r--r-- 1 app  app   7680 Mar  2 15:10 HelloNonRoot.dll
# -rw-r--r-- 1 app  app  20436 Mar  2 15:10 HelloNonRoot.pdb
# -rw-r--r-- 1 app  app    469 Mar  2 15:10 HelloNonRoot.runtimeconfig.json
# -rw-r--r-- 1 app  app    488 Mar  2 15:10 web.config
```

### Bonus : `apt-get update` en non-root

```bash
docker run -d --name non-root hello-nonroot:nonroot
docker exec -it non-root sh
$ apt-get update
# Reading package lists... Done
# E: List directory /var/lib/apt/lists/partial is missing. - Acquire (13: Permission denied)
```

> L'utilisateur `appuser` n'a pas les permissions pour modifier les fichiers système : un utilisateur non-root ne peut pas installer de paquets ni modifier la configuration du système.

## Récapitulatif des points abordés

| Bonne pratique                                   | Pourquoi                                                                               |
| ------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Ne jamais exécuter en `root` en production       | Réduit la surface d'attaque et limite l'impact d'une compromission                     |
| Créer un utilisateur système avec `useradd -r`   | Utilisateur sans home ni shell, dédié à l'exécution de l'application                   |
| Utiliser `COPY --chown`                          | Attribue les bons propriétaires sans layer supplémentaire                              |
| Placer `USER` après `COPY` et avant `ENTRYPOINT` | Le build nécessite parfois des permissions root, le runtime non                        |
| Utiliser `USER app` pour les images `.NET 8+`    | Utilisateur intégré, pas de `RUN` supplémentaire, approche recommandée par Microsoft   |
| `docker inspect --format '{{.Config.User}}'`     | Permet de vérifier l'utilisateur configuré dans une image                              |

---

[⬅️ 05-troubleshooting](../../tree/05-troubleshooting) ·
[📋 Sommaire](../../tree/main) ·
[07-securite-secrets ➡️](../../tree/07-securite-secrets)

[📝 Retour à l'énoncé](../../tree/06-securite-non-root)
