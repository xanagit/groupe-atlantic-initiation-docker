# Optimisation des stages Docker

[⬅️ 07-securite-secrets](../../tree/07-securite-secrets) ·
[📋 Sommaire](../../tree/main)

💡 [Voir la solution](../../tree/08-optimisation-stages--solution)

---

## Pourquoi optimiser les stages ?

Comme vu précédemment, `Docker` construit les images couche par couche (layers). Certaines instructions du `Dockerfile` (`FROM`, `COPY`, `RUN`, `ADD`) créent un nouveau layer. Ces layers sont mis en cache et réutilisés lors des builds suivants tant qu'ils n'ont pas été invalidés.

Une mauvaise organisation du Dockerfile peut entraîner :

* **Des rebuilds inutiles** : une modification mineure du code source déclenche le re-téléchargement de toutes les dépendances
* **Des layers superflus** : chaque `RUN` crée un layer, même si les commandes sont liées

Deux optimisations simples permettent d'améliorer significativement les temps de build et la taille de l'image :

1. Séparer le restore des dépendances de la compilation pour exploiter le cache `Docker`
2. Agréger les commandes `RUN` liées pour réduire le nombre de layers

### Le cache Docker

`Docker` utilise un mécanisme de cache (layers). Lors d'un build, chaque instruction est comparée à son équivalent en cache :

* Si l'instruction et le contexte (fichiers copiés, commande exécutée) n'ont pas changé, le layer en cache est réutilisé
* Si un layer est invalidé, tous les layers suivants sont également invalidés et reconstruits

### Problème : `COPY . .` avant `dotnet restore`

Dans un Dockerfile naïf, on copie tous les fichiers puis on restore les dépendances :

```dockerfile
COPY . .
RUN dotnet restore
RUN dotnet publish --configuration Release -o /app/publish
```

La commande `COPY . .` copie tous les fichiers sources. Dès qu'un seul fichier `.cs` change, le layer `COPY` est invalidé, ce qui force le `dotnet restore` à se ré-exécuter même si aucune dépendance n'a changé.

La solution pour éviter ce comportement est de copier d'abord uniquement le fichier `.csproj` (ou le fichier qui décrit les dépendances), exécuter le restore, puis copier le reste des sources :

```dockerfile
# Copie du seul csproj
COPY *.csproj .
# Restore (création d'un layer)
RUN dotnet restore
# copie des fichiers source
COPY . .
# Publish sans relancer le restore
RUN dotnet publish --configuration Release -o /app/publish --no-restore
```

> Le flag `--no-restore` de `dotnet publish` évite de relancer le restore puisqu'il a déjà été fait.

| Approche                      | Modification d'un `.cs`         | Modification du `.csproj`      |
| ----------------------------- | ------------------------------- | ------------------------------ |
| `COPY . .` puis `restore`     | ❌ Restore complet (cache raté) | ❌ Restore complet             |
| `COPY .csproj` puis `restore` | ✅ Restore en cache             | Restore complet (attendu)      |

### Problème : commandes `RUN` séparées

Chaque instruction `RUN` crée un layer distinct dans l'image. Quand plusieurs commandes sont liées (comme l'installation de paquets), les séparer pose deux problèmes :

#### 1. Layers inutiles et image plus volumineuse

```dockerfile
RUN apt-get update
RUN apt-get install -y curl
RUN rm -rf /var/lib/apt/lists/*
```

Le `rm` dans le troisième layer ne réduit pas la taille de l'image : les fichiers supprimés sont toujours présents dans les layers précédents. Les layers Docker sont immuables et additifs.

#### 2. Cache incohérent

Si le layer `apt-get update` est en cache mais que les dépôts ont été mis à jour côté serveur, `apt-get install` peut échouer ou installer une version obsolète.
Pour cette raison, il est préférable d'agréger les commandes liées en un seul `RUN` avec `&&` :

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    # Supression du cache local des indexes de paquets
    && rm -rf /var/lib/apt/lists/*
```

> Utiliser `\` pour les retours à la ligne et `&&` pour chaîner les commandes et donner une meilleur lisibilité. Le nettoyage (`rm -rf /var/lib/apt/lists/*`) dans le même `RUN` réduit réellement la taille du layer.

## Mise en pratique

### But

1. Identifier les impacts d'un `Dockerfile` non optimisé sur le cache et les layers
2. Optimiser la séparation `restore` / `publish` pour exploiter le cache `Docker`
3. Agréger les commandes `RUN` pour réduire le nombre de layers et la taille de l'image

### L'application

L'application reprend l'API web `ASP.NET Core 8.0` des exercices précédents. `curl` est installé dans l'image de runtime pour le `HEALTHCHECK`.

Endpoints exposés :

* `GET /` : JSON avec le titre et un message
* `GET /health` : JSON `{ "status": "up" }`

### Étape 1 — Identifier le comportement sans optimisation

Construire l'image à partir du `Dockerfile.naive` :

```bash
# Build de l'image
docker build -t hello-optimisation:naive -f Dockerfile.naive .
```

Vérifier que l'application fonctionne :

```bash
# Lancer le conteneur
docker run -d -p 8080:8080 --name opti-naive hello-optimisation:naive

# Tester l'API
curl -s http://localhost:8080 | jq
curl -s http://localhost:8080/health | jq
```

Vérifier le nombre de layers avec `docker history` :

```bash
docker history hello-optimisation:naive
```

Maintenant, modifier le code source sans changer les dépendances :

```bash
echo "\n// Nouveau commentaire" >> Program.cs
```

```bash
# Reconstruire l'image
docker build -t hello-optimisation:naive -f Dockerfile.naive .
```

> Observer la sortie du build : le `dotnet restore` est ré-exécuté alors qu'aucune dépendance n'a changé. Tout le build est relancé à partir de `COPY . .`.

### Étape 2 — Optimiser le cache avec la séparation restore / publish

Modifier le `Dockerfile.optimized` dans le stage `build` pour :

1. Copier d'abord uniquement le fichier `*.csproj`
2. Exécuter `dotnet restore`
3. Copier ensuite le reste des fichiers sources
4. Exécuter `dotnet publish` avec le flag `--no-restore`

Construire l'image et vérifier que l'application fonctionne :

```bash
# Build de l'image optimisée
docker build -t hello-optimisation:optimized -f Dockerfile.optimized .

# Lancer le conteneur
docker run -d -p 8080:8080 --name opti-optimized hello-optimisation:optimized

# Tester l'API
curl -s http://localhost:8080 | jq
```

Puis tester l'impact du cache en modifiant à nouveau `Program.cs` :

```bash
# Modifier le message dans Program.cs
echo "\n// Nouveau commentaire" >> Program.cs

# Reconstruire
docker build -t hello-optimisation:optimized -f Dockerfile.optimized .
```

> Cette fois, le `dotnet restore` utilise le cache (ligne `CACHED` dans la sortie du build). Seuls le `COPY . .` et le `dotnet publish` sont ré-exécutés.

### Étape 3 — Agréger les commandes `RUN`

Modifier `Dockerfile.aggregate` dans le stage `runtime` pour agréger les trois commandes `RUN` (`apt-get update`, `apt-get install` et `rm`) en une seule instruction.
Intégrer aussi les modification réalisées à l'étape précédente.

Reconstruire et comparer le nombre de layers :

```bash
# Rebuild
docker build -t hello-optimisation:aggregate -f Dockerfile.aggregate .

# Comparer les layers
docker history hello-optimisation:naive
docker history hello-optimisation:optimized
docker history hello-optimisation:aggregate
```

### Validation

* [ ] `docker build` se termine sans erreur pour les deux Dockerfiles
* [ ] `curl -s http://localhost:8080` retourne le JSON
* [ ] `curl -s http://localhost:8080/health` retourne `{ "status": "up" }`
* [ ] Après modification de `Program.cs`, le rebuild avec `Dockerfile.optimized` affiche `CACHED` pour le layer `dotnet restore`
* [ ] `docker history` montre moins de layers pour l'image optimisée que pour l'image `naive`
* [ ] L'application fonctionne correctement avec l'image optimisée

### Commandes de build & run

```bash
# Construire les versions
docker build -t hello-optimisation:naive -f Dockerfile.naive .
docker build -t hello-optimisation:optimized -f Dockerfile.optimized .
docker build -t hello-optimisation:aggregate -f Dockerfile.aggregate .

# Lancer les conteneurs
docker run -d -p 8080:8080 --name opti-naive hello-optimisation:naive
docker run -d -p 8080:8080 --name opti-optimized hello-optimisation:optimized
docker run -d -p 8080:8080 --name opti-aggregate hello-optimisation:aggregate
```

Commandes utiles :

```bash
# Tester l'API
curl -s http://localhost:8080 | jq
curl -s http://localhost:8080/health | jq

# Comparer les layers
docker history hello-optimisation:naive
docker history hello-optimisation:optimized
docker history hello-optimisation:aggregate

# Voir le nombre de layers
docker history hello-optimisation:naive | wc -l
docker history hello-optimisation:optimized | wc -l
docker history hello-optimisation:aggregate | wc -l

# Comparer les tailles
docker image ls hello-optimisation
```

### Bonus

* Comparer les temps de rebuild avec `time docker build ...` après une modification de `Program.cs`

### Liens utiles

* [Documentation sur le cache de build](https://docs.docker.com/build/cache/)
* [Documentation sur les bonnes pratiques Dockerfile](https://docs.docker.com/build/building/best-practices/)
* [Optimiser les layers](https://docs.docker.com/build/cache/optimize/)
* [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)

---

[⬅️ 07-securite-secrets](../../tree/07-securite-secrets) ·
[📋 Sommaire](../../tree/main)

💡 [Voir la solution](../../tree/08-optimisation-stages--solution)

---
