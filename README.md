# Les fichiers `.dockerignore` et `Dockerfile.dockerignore` : solution

[⬅️ 03-env-args](../../tree/03-env-args) ·
[📋 Sommaire](../../tree/main) ·
[05-troubleshooting ➡️](../../tree/05-troubleshooting)

[📝 Retour à l'énoncé](../../tree/04-dockerignore)

---

## Rappel de l'objectif

Mettre en place les fichiers `.dockerignore` et `Dockerfile.dockerignore` pour réduire le build context, protéger les fichiers sensibles et gérer les exclusions par Dockerfile.

## Solution

### Étape 1 — Observer la taille des images sans `.dockerignore`

Préparation (builds locaux) :

```bash
# Lancer les commandes de récupération des dépendances et de build
# Backend
cd backend
dotnet restore
dotnet publish --configuration Release -o publish
# frontend
cd ../frontend
npm install
npm run build
```

Build sans `.dockerignore` :

```bash
# Build du frontend
cd frontend
docker build -t hello-dockerignore-front:noignore -f Dockerfile.front .
# [+] Building ...
# => [internal] load build context
# => => transferring context: XXX MB
# ... 
```

```bash
# Build du backend
cd ../backend
docker build -t hello-dockerignore-back:noignore -f Dockerfile.back .
# [+] Building ...
# => [internal] load build context
# => => transferring context: XXX MB
# ...
```

Lancement du backend et du frontend :

```bash
docker run -d -p 3000:3000 hello-dockerignore-front:noignore
docker run -d -p 8080:8080 hello-dockerignore-back:noignore
```

Lancement de l'application dans un navigateur : [Front](http://localhost:3000)

#### Inspection de l'image du frontend

Vérification de la taille des images :

```bash
docker image ls hello-dockerignore-front
IMAGE                             CONTENT SIZE
hello-dockerignore-front:noignore        189MB
```

Vérification des fichiers dans l'image du frontend :

```bash
docker run --rm hello-dockerignore-front:noignore ls -la /app
docker run --rm hello-dockerignore-front:noignore ls -la /app
# drwxr-xr-x  build
# -rwxr-xr-x  entrypoint.sh
# -rw-r--r--  .DS_Store         => inutile au runtime
# -rw-r--r--  .env              => inutile et contient potentiellement des secrets
# drwxr-xr-x  .git              => ne sert à rien au runtime
# -rw-r--r--  .gitignore        => ne sert à rien au runtime
# -rw-r--r--  Dockerfile.front  => ne doit pas être contenue dans l'image finale
# -rw-r--r--  README.md         => inutile
# drwxr-xr-x  images            => alourdi l'image inutilement
# -rw-r--r--  key.pem           => fichier sensible, ne devrait pas être stocké ici
# drwxr-xr-x  node_modules      => inutile
# -rw-r--r--  package-lock.json => inutile
# -rw-r--r--  package.json      => inutile
# drwxr-xr-x  public            => inutile, déjà contenu dans build
# drwxr-xr-x  src               => inutile, déjà contenu dans build

docker run --rm hello-dockerignore-front:noignore du -skh /app
# 356.5M    ← volumineux à cause de node_modules
```

> Le `Dockerfile.front` n'est pas multi-stage : le `COPY . .` copie tout le répertoire dans l'image finale.
> On retrouve donc `node_modules/`, `src/`, `public/`, les images et même `key.pem` dans l'image.

#### Vérifier les fichiers dans le stage de build du backend

Le Dockerfile `Dockerfile.back` est en multi-stage : le stage runtime ne contient que le répertoire `publish`. Mais le stage build a quand même reçu tous les fichiers :

```bash
# Build en arrêtant la construction à la fin du stage de build
docker build --target build -t hello-dockerignore-back:build-stage -f Dockerfile.back .

docker run --rm hello-dockerignore-back:build-stage ls -la /src
# -rw-r--r-- .DS_Store
# drwxr-xr-x .git
# -rw-r--r-- .gitignore
# drwxr-xr-x .vscode
# -rw-r--r-- Dockerfile.back
# -rw-r--r-- Dockerfile.debug
# -rw-r--r-- HelloDockerignore.csproj
# -rw-r--r-- Program.cs
# -rw-r--r-- README.md
# drwxr-xr-x bin
# drwxr-xr-x images
# drwxr-xr-x obj
# drwxr-xr-x publish
```

> Même si l'image finale du backend est légère grâce au multi-stage, les fichiers inutiles sont tout de même envoyés au daemon Docker, ce qui ralentit le build et peut invalider le cache inutilement.

### Étape 2 — Créer les `.dockerignore`

#### `.dockerignore` du frontend (`frontend/.dockerignore`)

```Dockerfile
# Dossiers liés au build local
build/
node_modules/

# Fichiers VCS (git)
.git/
.gitignore

# Fichiers Docker
Dockerfile*
*.dockerignore

# Fichiers sensibles
*.key
*.pem

# Documentation
images/
README.md
```

#### Explication des exclusions du frontend

| Pattern          | Ce qui est exclu         | Pourquoi                                                         |
| ---------------- | ------------------------ | ---------------------------------------------------------------- |
| `node_modules/`  | Dépendances locales      | Réinstallé par `npm ci` dans le conteneur                        |
| `build/`         | Build local React        | Inutile : le build se fait dans le conteneur via `npm run build` |
| `*.pem` `*.key`  | Fichiers sensibles       | `key.pem` ne doit jamais se retrouver dans l'image               |
| `images/`        | Assets non liés au build | Alourdit le build context inutilement                            |
| `Dockerfile*`    | Fichiers Docker          | Ne fait pas partie de l'application                              |

#### `.dockerignore` du backend (`backend/.dockerignore`)

```Dockerfile
# Lié au build local
bin/
obj/
publish/

# Fichiers VCS (git)
.git/
.gitignore

# Fichiers Docker
Dockerfile*
*.dockerignore

# Documentation
images/
README.md
```

#### Explication des exclusions du backend

| Pattern       | Ce qui est exclu         | Pourquoi                                                       |
| ------------- | ------------------------ | -------------------------------------------------------------- |
| `bin/` `obj/` | Compilation locale       | Inutile : le `dotnet restore` se fait dans le conteneur        |
| `publish/`    | Publication locale       | Inutile : le publish se fait dans le stage build du conteneur  |
| `images/`     | Assets non liés au build | Alourdit le build context                                      |
| `Dockerfile`  | Fichiers Docker          | Ne fait pas partie de l'application                            |

#### Rebuild et comparaison

> Pour réellement minimiser la taille de l'image du frontend, il est nécessaire de convertir le `Dockerfile` en multi-stage build sous peine d'embarquer les `node_modules` au runtime. Pour cela, on va utiliser `Dockerfile.multi` :

```bash
# Rebuild du frontend
cd frontend
docker build -t hello-dockerignore-front:ignore -f Dockerfile.multi .
# => [internal] load build context
# => => transferring context: ...

# Rebuild du backend
cd ../backend
docker build -t hello-dockerignore-back:ignore -f Dockerfile.back .
# => [internal] load build context
# => => transferring context: ~10kB
# ...
```

Comparaison des tailles d'image du **frontend** (là où le `.dockerignore` a le plus d'impact car il n'est pas multi-stage) :

```bash
docker image ls hello-dockerignore-front
# REPOSITORY                         CONTENT SIZE
# hello-dockerignore-front:noignore         189MB
# hello-dockerignore-front:ignore          52.9MB
```

Vérification du contenu de l'image du frontend :

```bash
docker run --rm hello-dockerignore-front:ignore ls -la /app
# -rwxr-xr-x  ... entrypoint.sh
# -rw-r--r--  ... package.json
# -rw-r--r--  ... package-lock.json
# drwxr-xr-x  ... build/             ← généré par npm run build dans le conteneur
# drwxr-xr-x  ... node_modules/      ← installé par npm ci dans le conteneur
```

> `key.pem`, `images/`, `src/`, `public/`, `Dockerfile.front` et `README.md` ont disparu.

Pour le backend, la taille de l'image finale ne change pas grâce au multi-stage, mais le build context est réduit, ce qui accélère la vitesse de build et diminue la taille des layers :

```bash
docker image ls hello-dockerignore-back
# REPOSITORY                      CONTENT SIZE
# hello-dockerignore-back:ignore          88MB (identique)
```

> Le multi-stage permet de minimiser la taille de l'image finale même sans `.dockerignore` mais il reste essentiel pour :
>
> * **Accélérer le transfert** du build context vers le daemon Docker (données limitées envoyées)
> * **Préserver le cache** : sans `.dockerignore`, un changement dans `bin/`, `obj/` ou `images/` invalide le cache de `COPY . .` et force un rebuild complet (`dotnet restore` + `dotnet publish`)

### Étape 3 — Créer un `Dockerfile.debug.dockerignore` spécifique

Le `Dockerfile.debug` utilise un seul stage avec le SDK complet. Il installe `vsdbg` (le debugger VS Code pour .NET) et exécute l'application en mode Debug avec `dotnet run`.
Pour information, la configuration de debug est utilisée à titre d'exemple mais n'est pas fonctionnelle.

Le `.dockerignore` global exclut `Dockerfile*`, y compris `Dockerfile.debug` lui-même. On peut créer un `Dockerfile.debug.dockerignore` avec des règles différentes adaptées au contexte de debug :

```Dockerfile
# Dossiers liés au build local
bin/
obj/
publish/

# Fichiers VCS (git)
.git/
.gitignore

# Fichiers Docker
Dockerfile.back
*.dockerignore

# Documentation
images/
README.md
```

> Lors du build avec `Dockerfile.debug` (`docker build -f Dockerfile.debug`), docker cherche a utiliser en priorité le fichier `Dockerfile.debug.dockerignore`. S'il ne le trouve pas, le fichier `.dockerignore` est utilisé. Cela permet d'avoir différentes configurations `dockerignore` en fonction du build réalisé.

#### Build et vérification

```bash
cd backend

# Build avec le Dockerfile.debug (utilise automatiquement Dockerfile.debug.dockerignore)
docker build -t hello-dockerignore-back:debug -f Dockerfile.debug .
```

Vérification que le `.dockerignore` spécifique est bien appliqué :

```bash
# La configuration .vscode est gardé dans l'image finale (ce n'est pas le cas avec Dockerfile.back)
docker run --rm hello-dockerignore-back:debug ls .vscode
# launch.json
```

### Bonus : impact sur le temps de build et le cache

#### Mesurer le temps de build

```bash
cd frontend

# Sans .dockerignore (renommer temporairement le fichier)
mv .dockerignore .dockerignore.back
time docker build --no-cache -t hello-dockerignore-front:noignore -f Dockerfile.front .
# docker build --no-cache -t hello-dockerignore-front:noignore -f  .  2,25s user 4,68s system 22% cpu 30,474 total

# Avec .dockerignore
mv .dockerignore.back .dockerignore
time docker build --no-cache -t hello-dockerignore-front:ignore -f Dockerfile.multi .
# docker build --no-cache -t hello-dockerignore-front:ignore -f Dockerfile.multi  0,09s user 0,09s system 1% cpu 12,586 total
```

#### Analyser les layers avec `docker image history`

```bash
docker image history hello-dockerignore-front:noignore
# IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
# ...
# <missing>      3 minutes ago   COPY . . # buildkit                             374MB     buildkit.dockerfile.v0

docker image history hello-dockerignore-front:ignore
# IMAGE          CREATED              CREATED BY                                      SIZE      COMMENT
# ...
# <missing>      About a minute ago   COPY /app/build /app # buildkit                 532kB     buildkit.dockerfile.v0
```

#### Tester l'invalidation du cache

```bash
cd frontend

# Premier build
docker build -t hello-dockerignore-front:cache-test -f Dockerfile.front .

# Modifier le README (fichier exclu par .dockerignore)
echo "modification" >> README.md

# Rebuilder : le cache est toujours valide ✅
docker build -t hello-dockerignore-front:cache-test -f Dockerfile.multi .
# [+] Building 0.1s (14/14) FINISHED                                                                                                                     docker:colima
# ...                                                                                                                     0.0s
#  => CACHED [build 3/5] COPY . .  => Cache non modifié
```

> Sans `.dockerignore`, la modification du `README.md` aurait invalidé le cache de `COPY . .` et déclenché un rebuild complet : `npm ci` + `npm run build`.

## Récapitulatif des points abordés

| Bonne pratique                                       | Pourquoi                                                               |
| ---------------------------------------------------- | ---------------------------------------------------------------------- |
| Toujours créer un `.dockerignore`                    | Réduit le build context, protège les secrets et le cache               |
| Exclure `bin/`, `obj/`, `node_modules/`              | La compilation et l'installation se font dans le conteneur             |
| Exclure `*.pem`, `*.key`                             | Empêcher les fuites de secrets dans l'image                            |
| Exclure `Dockerfile*`                                | Les Dockerfiles ne font pas partie de l'application                    |
| `Dockerfile.dockerignore`                            | Gère les exclusions différentes par Dockerfile                         |
| `Dockerfile.X.dockerignore` remplace `.dockerignore` | Il faut re-lister toutes les exclusions du `Dockerfile` (pas de merge) |
| Le multi-stage ne suffit pas                         | Il protège l'image finale mais pas le build context ni le cache        |
| `docker build --target`                              | Inspecte le contenu des stages intermédiaires                          |
| `docker image history`                               | Analyser la taille de chaque layer                                     |

---

[⬅️ 03-env-args](../../tree/03-env-args) ·
[📋 Sommaire](../../tree/main) ·
[05-troubleshooting ➡️](../../tree/05-troubleshooting)

[📝 Retour à l'énoncé](../../tree/04-dockerignore)
