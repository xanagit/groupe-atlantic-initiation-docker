# Optimisation des stages Docker : solution

[⬅️ 07-securite-secrets](../../tree/07-securite-secrets) ·
[📋 Sommaire](../../tree/main)

[📝 Retour à l'énoncé](../../tree/08-optimisation-stages)

---

## Rappel de l'objectif

Identifier les impacts d'un `Dockerfile` non optimisé sur le cache et les layers, optimiser la séparation `restore` / `publish` pour exploiter le cache Docker, et agréger les commandes `RUN` pour réduire le nombre de layers.

## Solution

### Étape 1 — Identifier le comportement sans optimisation

#### Build et lancement

```bash
# Build de l'image naive
docker build -t hello-optimisation:naive -f Dockerfile.naive .

# Lancer le conteneur
docker run -d -p 8080:8080 --name opti-naive hello-optimisation:naive
```

#### Vérification de l'API

```bash
curl -s http://localhost:8080 | jq
# {
#   "title": "Hello Optimisation !",
#   "message": "L'application a été construite avec succès !"
# }

curl -s http://localhost:8080/health | jq
# { "status": "up" }
```

#### Observer les layers

```bash
docker history hello-optimisation:naive
# CREATED BY                                      SIZE
# HEALTHCHECK &{["CMD-SHELL" "curl -f http://l…   0B
# COPY --chown=app /app/publish . # buildkit      285kB
# RUN /bin/sh -c rm -rf /var/lib/apt/lists/*      0B
# RUN /bin/sh -c apt-get install -y --no-insta…   41.5MB
# RUN /bin/sh -c apt-get update # buildkit        26.5MB
# ...            ...
```

> On voit 3 layers distincts pour l'installation de `curl` : `apt-get update`, `apt-get install` et `rm`. Le layer `rm` fait `0B` car les fichiers supprimés sont toujours présents dans les layers précédents — la suppression n'a aucun effet sur la taille finale de l'image.

#### Simuler une modification du code source

```bash
# Ajouter un commentaire dans Program.cs
echo "\n// Nouveau commentaire" >> Program.cs

# Reconstruire l'image
docker build -t hello-optimisation:naive -f Dockerfile.naive .
# => [build 3/5] COPY . .                                                          0.0s
#  => [build 4/5] RUN dotnet restore                                               0.5s
#  => [build 5/5] RUN dotnet publish --configuration Release -o /app/publish       1.5s
```

> Le `dotnet restore` est ré-exécuté (pas de `CACHED`) alors qu'aucune dépendance n'a changé. Le `COPY . .` invalide le cache car un fichier source a été modifié, et tous les layers suivants (y compris le restore) sont reconstruits en cascade.

### Étape 2 — Optimiser le cache avec la séparation restore / publish

#### `Dockerfile.optimized`

```dockerfile
...
# Copie du seul fichier csproj (décrit les dépendances)
COPY *.csproj .

# Restore des dépendances (ce layer est mis en cache tant que le csproj ne change pas)
RUN dotnet restore

# Copie du reste des fichiers sources
COPY . .

# Publish sans relancer le restore (déjà fait et en cache)
RUN dotnet publish --configuration Release -o /app/publish --no-restore

...
```

> Le `COPY *.csproj .` ne copie que le fichier de description des dépendances. Le layer `RUN dotnet restore` est mis en cache et ne sera invalidé que si le `.csproj` change (ajout/suppression d'un package `NuGet`). Les modifications de fichiers `.cs` n'invalident plus le restore. Le flag `--no-restore` de `dotnet publish` est indispensable pour éviter de relancer un restore implicite qui annulerait le bénéfice de la séparation.

#### Build et vérification du cache

```bash
# Premier build (tout est construit)
docker build -t hello-optimisation:optimized -f Dockerfile.optimized .
```

#### Test de l'optimisation du cache

```bash
# Modifier le code source
echo "\n// Nouveau commentaire" >> Program.cs

# Reconstruire
docker build -t hello-optimisation:optimized -f Dockerfile.optimized .
# => CACHED [build 2/6] WORKDIR /app                                                                                                                             0.0s
# => CACHED [build 3/6] COPY *.csproj .                                                                                                                          0.0s
# => CACHED [build 4/6] RUN dotnet restore                                                                                                                       0.0s
# => [build 5/6] COPY . .                                                                                                                                        0.0s
# => [build 6/6] RUN dotnet publish --configuration Release -o /app/publish --no-restore
```

> Le `dotnet restore` affiche `CACHED` : les dépendances ne sont pas re-téléchargées. Seuls le `COPY . .` et le `dotnet publish` sont ré-exécutés.

### Étape 3 — Agréger les commandes `RUN`

#### `Dockerfile.aggregate`

```dockerfile
# ---------- Stage 1 : Build ----------
...

# Installation de curl pour le HEALTHCHECK : commandes agrégées en un seul layer
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

...
```

> Les trois commandes `apt-get update`, `apt-get install` et `rm -rf` sont regroupées dans un seul `RUN` avec `&&`. Le nettoyage du cache apt (`rm -rf /var/lib/apt/lists/*`) dans le même layer réduit réellement la taille de l'image car les fichiers supprimés ne sont jamais écrits dans un layer séparé.

#### Build et comparaison des layers

```bash
# Build de l'image agrégée
docker build -t hello-optimisation:aggregate -f Dockerfile.aggregate .

# Comparer les layers
docker history hello-optimisation:naive
# ...
# <missing> RUN /bin/sh -c rm -rf /var/lib/apt/lists/* #…   20.5kB
# <missing> RUN /bin/sh -c apt-get install -y --no-insta…   6.25MB
# <missing> RUN /bin/sh -c apt-get update # buildkit        19.5MB

docker history hello-optimisation:optimized
# ...
# <missing> RUN /bin/sh -c rm -rf /var/lib/apt/lists/* #…   20.5kB
# <missing> RUN /bin/sh -c apt-get install -y --no-insta…   6.25MB
# <missing> RUN /bin/sh -c apt-get update # buildkit        19.5MB

docker history hello-optimisation:aggregate
# <missing>      About a minute ago   RUN /bin/sh -c apt-get update   && apt-get i…   6.25MB    buildkit.dockerfile.v0
```

> L'agrégation des commandes permet de faire gagner quelques `MB` à l'image finale.

#### Comparaison du nombre de layers

```bash
docker history hello-optimisation:naive | wc -l
# ~18 => 17 sans le header

docker history hello-optimisation:optimized | wc -l
# ~18 => 17 sans le header

docker history hello-optimisation:aggregate | wc -l
# ~16 => 15 sans le header
```

> L'image `aggregate` a 2 layers de moins que les deux autres car les 3 `RUN apt-get` sont fusionnés en un seul.

#### Comparaison des tailles d'image

```bash
docker image ls hello-optimisation
# IMAGE                        CONTENT SIZE
# hello-optimisation:naive            106MB
# hello-optimisation:optimized        106MB
# hello-optimisation:aggregate       90.6MB
```

> L'image `aggregate` est plus légère car le `rm -rf /var/lib/apt/lists/*` dans le même layer que `apt-get update` supprime effectivement les fichiers d'index. Dans les versions `naive` et `optimized`, le `rm` est dans un layer séparé : les fichiers d'index restent dans le layer `apt-get update` et occupent de l'espace.

### Bonus : comparaison des temps de rebuild

```bash
# Modifier Program.cs
echo "\n// test" >> Program.cs

# Comparer les temps de rebuild
time docker build -t hello-optimisation:naive -f Dockerfile.naive .
# ...
# docker build -t hello-optimisation:naive -f Dockerfile.naive .  0,09s user 0,06s system 5% cpu 2,573 total

time docker build -t hello-optimisation:optimized -f Dockerfile.optimized .
# ...
# docker build -t hello-optimisation:optimized -f Dockerfile.optimized .  0,08s user 0,06s system 7% cpu 0,518 total

time docker build -t hello-optimisation:aggregate -f Dockerfile.aggregate .
# ...
# docker build -t hello-optimisation:aggregate -f Dockerfile.aggregate .  0,08s user 0,06s system 32% cpu 0,402 total
```

> Les images `optimized` et `aggregate` sont plus rapides à reconstruire car le `dotnet restore` est en cache. Le gain dépend du nombre de dépendances NuGet du projet.

## Récapitulatif des points abordés

| Bonne pratique                                      | Pourquoi                                                                                           |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `COPY *.csproj` avant `dotnet restore`              | Le restore n'est relancé que si les dépendances changent, pas à chaque modification de code source |
| `--no-restore` sur `dotnet publish`                 | Évite un restore implicite qui annulerait le bénéfice de la séparation                             |
| Agréger les `RUN` liés avec `&&`                    | Réduit le nombre de layers et permet au nettoyage (`rm`) d'être effectif dans le même layer        |
| `rm -rf /var/lib/apt/lists/*` dans le même `RUN`    | La suppression des index apt dans le même layer réduit la taille de l'image                        |
| Placer les instructions les moins volatiles en haut | Les layers stables (restore, install) restent en cache quand seul le code source change            |

---

[⬅️ 07-securite-secrets](../../tree/07-securite-secrets) ·
[📋 Sommaire](../../tree/main)

[📝 Retour à l'énoncé](../../tree/08-optimisation-stages)

---
