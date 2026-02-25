# Build Multi-Stage

[⬅️ 01-dockerisation-simple](../../tree/01-dockerisation-simple) ·
[📋 Sommaire](../../tree/main) ·
[03-env-args ➡️](../../tree/03-env-args)

[💡 Voir la solution](../../tree/02-multi-stage--solution)

---

## Pourquoi le multi-stage ?

Lorsqu'on conteneurise une application compilée (`C#`, `Java`, `Go`, ...), le processus de build nécessite des outils lourds (SDK, compilateur, dépendances de développement) qui n'ont pas d'utilité en production.

Sans multi-stage, on se retrouve avec une image qui contient tout : le SDK, le code source, les fichiers intermédiaires de compilation avec le binaire final => l'image est volumineuse, lente à transférer et présente une surface d'attaque élargie.

Le build multi-stage résout ce problème en découpant le `Dockerfile` en plusieurs étapes (`FROM`). Chaque étape produit un environnement (stage) temporaire et seuls les artefacts nécessaires sont copiés d'un stage à l'autre via `COPY --from=<stage>`.

### Avantages

| Critère                  | Sans multi-stage                            | Avec multi-stage                        |
| ------------------------ | ------------------------------------------- | --------------------------------------- |
| Taille de l'image        | Très volumineuse (SDK + sources + binaires) | Réduite (runtime + binaires uniquement) |
| Surface d'attaque        | Large (compilateur, outils de dev présents) | Minimale (que le strict nécessaire)     |
| Temps de pull / push     | Long                                        | Court                                   |

### Principe

```dockerfile
# ---------- Stage 1 : Build ----------
FROM sdk-image AS build
WORKDIR /src
COPY . .
RUN <commande de compilation / publication>

# ---------- Stage 2 : Runtime ----------
FROM runtime-image AS final
WORKDIR /app
COPY --from=build /src/<output> .
ENTRYPOINT ["<commande de démarrage>"]
```

> **Point clé** : `COPY --from=build` copie les fichiers depuis le stage nommé `build` vers le stage courant. Le stage `build` (et tout son contenu : SDK, sources, fichiers intermédiaires) n'est pas gardé dans l'image finale.

### Écosystème d'images .NET

Microsoft fournit principalement deux images Docker officielles pour les appplications `.NET`. Elles sont hébergées sur le Microsoft Container Registry (`mcr.microsoft.com`) :

- Image de `build` :
  - Image: `mcr.microsoft.com/dotnet/sdk:8.0`
  - Contenu : SDK complet (.NET CLI + runtime + ASP.NET Core)
- Image de `run` :
  - Image: `mcr.microsoft.com/dotnet/aspnet:8.0`
  - Contenu : Runtime ASP.NET Core

## Mise en pratique

### But

Le Dockerfile `Dockerfile.single` build l'application `ASP.NET` Core Web API présente dans cette branche. Adapter le Dockerfile et le rendre multi-stage afin de produire une image de production légère.

### L'application

L'application consiste en une API web minimaliste (ASP.NET Core 8.0) qui expose deux endpoints :

- `GET /` : JSON avec un titre et un message
- `GET /health` | JSON `{ "status": "up" }`

Commande de lancement locale (nécessite le SDK .NET 8) :

```bash
dotnet restore
dotnet run

# Tests
# Sur /
curl -s http://localhost:5000
# {"title":"Hello Multi-Stage !","message":"Le endpoint / fonctionne correctement !"}
# Sur /health
curl -s http://localhost:5000/health
# {"status":"up"}
```

### Étape 1 — Dockerfile single-stage

Utiliser le Dockerfile `Dockerfile.single` pour construire l'image :

```bash
# Construire l'image single-stage
docker build -t hello-multistage:single -f Dockerfile.single .

# Vérifier la taille
docker image ls hello-multistage:single
```

> 💡 La taille devrait être autour de **~300 MB**.

### Étape 2 — Dockerfile multi-stage

Partir du Dockerfile `Dockerfile.multi` et le modifier pour le transformer en build multi-stage :

1. **Stage `build`** : utiliser `mcr.microsoft.com/dotnet/sdk:8.0` comme image de base, nommé `build`

2. **Stage `runtime`** : utiliser `mcr.microsoft.com/dotnet/aspnet:8.0` comme image de base

Construire l'image et comparer la taille avec l'image générée précédemment.

```bash
# Construire l'image multi-stage
docker build -t hello-multistage:multi -f Dockerfile.multi .

# Comparer les tailles
docker image ls hello-multistage
```

### Validation

- [ ] `docker build` se termine sans erreur
- [ ] `docker run -p 8080:8080 hello-multistage:multi` démarre le conteneur
- [ ] `curl -s http://localhost:8080` retourne le JSON contenant le message, le framework et le timestamp
- [ ] `curl -s http://localhost:8080/health` retourne le statut healthy
- [ ] La taille de l'image multi-stage est significativement inférieure à celle du single-stage

### Commandes de build & run

```bash
# Construire les deux versions pour comparer
docker build -t hello-multistage:single -f Dockerfile.single .
docker build -t hello-multistage:multi -f Dockerfile.multi .

# Lancer le conteneur
docker run -p 8080:8080 hello-multistage:multi
# En mode detached
docker run -p 8080:8080 -d hello-multistage:multi
# En mode detached avec un nom
docker run -p 8080:8080 -d --name hello-multistage-multi hello-multistage:multi
```

Commandes utiles :

```bash
# Comparer les tailles des images
docker image ls hello-multistage

# Tester l'API
curl -s http://localhost:8080 | jq
curl -s http://localhost:8080/health | jq
```

### Bonus

- Utiliser une variante Alpine de l'image de runtime (`aspnet:9.0-alpine`) pour réduire encore la taille
- Ajouter un `HEALTHCHECK` basé sur l'endpoint `/health`
- Vérifier la gestion build-in des handlers `SIGINT` et `SIGTERM` de `.NET`

### Liens utiles

- [Documentation multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Images .NET sur MCR](https://mcr.microsoft.com/catalog?search=dotnet)
- [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)

---

[⬅️ 01-dockerisation-simple](../../tree/01-dockerisation-simple) ·
[📋 Sommaire](../../tree/main) ·
[03-env-args ➡️](../../tree/03-env-args)

[💡 Voir la solution](../../tree/02-multi-stage--solution)
