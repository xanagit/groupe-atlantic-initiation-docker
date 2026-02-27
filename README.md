# Les fichiers `.dockerignore` et `Dockerfile.dockerignore`

[⬅️ 03-env-args](../../tree/03-env-args) ·
[📋 Sommaire](../../tree/main) ·
[05-troubleshooting ➡️](../../tree/05-troubleshooting)

💡 [Voir la solution](../../tree/04-dockerignore--solution)

---

## Utilité du `.dockerignore` ?

Lorsqu'on exécute `docker build`, les commandes `COPY` envoient l'intégralité du répertoire courant passé en argument : les sources, les binaires compilés, le répertoire `.git/`, les fichiers de configuration locaux, les secrets, etc.

Cela pose plusieurs problèmes :

* Fichiers inutiles copiés : build plus lent
* Invalidation du cache : un changement dans un fichier non pertinent (ex: `.git/`) invalide le cache de `COPY` et déclenche un rebuild complet
* Sécurité : des fichiers sensibles (`.env` ou secrets) peuvent se retrouver dans l'image
* Taille de l'image : des fichiers non nécessaires alourdissent l'image finale

### Fonctionnement du fichier `.dockerignore`

Le fichier `.dockerignore` fonctionne comme un `.gitignore` : il indique à Docker les fichiers et répertoires à exclure du contexte du build.

Exemple de fichier `.dockerignore` :

```Dockerfile
# Fichiers de compilation .NET
bin/
obj/

# Répertoire Git
.git/
.gitignore

# Fichiers IDE
.vs/
.vscode/
*.sln
*.user

# Fichiers Docker
Dockerfile*
docker-compose*

# Fichiers sensibles
.env
*.key
*.pem
```

> Le fichier `.dockerignore` est lu avant l'exécution du build : les fichiers exclus ne sont jamais envoyés dans l'image pour améliorer la performance et la sécurité.

### Le fichier `Dockerfile.dockerignore`

Depuis `Docker BuildKit` (nouveau moteur de build Docker utilisé par défaut depuis `Docker 23`), il est possible de créer un fichier `.dockerignore` spécifique à un Dockerfile. La convention de nommage est `<nom-du-dockerfile>.dockerignore`.

Par exemple :

```bash
.
├── Dockerfile.dev
├── Dockerfile.dev.dockerignore  # fichiers ignorés par le build de Dockerfile.dev
├── Dockerfile.prod
├── Dockerfile.prod.dockerignore # fichiers ignorés par le build de Dockerfile.prod
├── Dockerfile.preprod
└── .dockerignore # Utilisé lors du build de Dockerfile.preprod 
                  # car il n'a pas de .dockerignore dédié
```

C'est utile quand on a plusieurs Dockerfiles dans le même répertoire avec des besoins différents :

* Un Dockerfile de dev qui a besoin des fichiers de test et de config locale
* Un Dockerfile de prod qui doit exclure tout ce qui n'est pas nécessaire au runtime
* Peut aussi être utile dans un mono-repo : chaque application a son `Dockerfile` dédié

> Si un fichier `Dockerfile.prod.dockerignore` existe, il est utilisé en remplacement de `.dockerignore` (pas en complément). Toutes les exclusions nécessaires au build `Dockerfile.prod` doivent être définies dans `Dockerfile.prod.dockerignore`.

## Mise en pratique

### But

Ajouter les fichiers `.dockerignore` et `Dockerfile.dockerignore` sur le projet de l'exercice précédent pour :

1. Observer la taille des images sans `.dockerignore`
2. Créer les `.dockerignore`
3. Créer un `.dockerignore` spécifique à un Dockerfile

### L'application

L'application comprend un backend en `C#` et un frontend en `React.js`. La variable d'environnement `FRONT_ORIGIN` a été ajoutée au build du backend pour configurer les `CORS`.
Le front contient un script de démarrage qui injecte la variable d'environnement `BACKEND_URL` dans le front au démarrage.

### Préparation — Simuler des fichiers à exclure

Avant de commencer, créer quelques fichiers et répertoires qui simulent un projet réel :

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

### Étape 1 — Observer la taille des images sans `.dockerignore`

Construire les images des projets backend et frontend sans `.dockerignore` :

```bash
# Build du frontend
cd frontend
docker build -t hello-dockerignore-front:noignore -f Dockerfile.front .
# Build du backend
cd ../backend
docker build -t hello-dockerignore-back:noignore -f Dockerfile.back .
```

Lancer les conteneurs :

```bash
docker run -d -p 3000:3000 hello-dockerignore-front:noignore
docker run -d -p 8080:8080 hello-dockerignore-back:noignore
```

Lancer l'application dans un navigateur : [Front](http://localhost:3000)

Vérifier la taille des images finales :

```bash
docker image ls hello-dockerignore-front
docker image ls hello-dockerignore-back
```

Vérifier les fichiers présents dans l'image du frontend et la taille du répertoire `/app` :

```bash
# Lister tous les fichiers
docker run --rm -it hello-dockerignore-front:noignore ls -la /app
# Afficher la taille occupée
docker run --rm -it hello-dockerignore-front:noignore du -skh /app
```

> Le build du backend est structuré en multi-stage build : la taille du stage de build sera volumineuse
> mais la taille de l'image finale sera réduite car le stage runtime n'embarque que le répertoire `publish` du tag `build`.

### Étape 2 — Créer les `.dockerignore`

Créer un fichier `.dockerignore` à la racine de chaque projet (backend et frontend) qui exclut :

1. Les répertoires de compilation `C#` (`bin/`, `obj/`) ou node (`node_modules`)
2. Le répertoire Git (`.git/`, `.gitignore`)
3. Les fichiers Docker (`Dockerfile*`)
4. Les fichiers sensibles (`.env`, `*.pem`)
5. La documentation (`docs/`, `README.md`)

Reconstruire les images et comparer les tailles d'image avec et sans `.dockerignore` :

```bash
docker build -t hello-dockerignore-front:ignore -f Dockerfile.front .
docker build -t hello-dockerignore-back:ignore -f Dockerfile.back .
```

Comparer la taille des images :

```bash
docker image ls hello-dockerignore-front
docker image ls hello-dockerignore-back
```

Vérifier que seulement les fichiers nécessaires au runtime sont dans l'image du frontend :

```bash
docker run --rm -it hello-dockerignore-front:ignore ls -la /app
```

### Étape 3 — Créer un `Dockerfile.dockerignore` spécifique

Dans le backend, créer un fichier `Dockerfile.debug.dockerignore` qui :

* Reprend les mêmes exclusions que le `.dockerignore`
* Mais autoriser le répertoire `.vscode` nécessaire pour le debug

Construire l'image et vérifier que `.vscode` est présent :

```bash
cd backend
# Build de l'image debug
docker build -t hello-dockerignore:debug -f Dockerfile.debug .
# Run de l'image debug
docker run --rm -it hello-dockerignore:debug ls -la /app/.vscode
```

### Validation

* [ ] L'image du frontend est significativement plus petite avec le `.dockerignore`
* [ ] Les fichiers sensibles (`.env`, `key.pem`) ne sont pas présents dans l'image du frontend
* [ ] Le `Dockerfile.debug.dockerignore` permet d'inclure `.vscode/` uniquement pour le build debug
* [ ] Les fichiers de compilation (`bin`, `obj`) ne sont pas dans l'image

### Commandes de build & run

```bash
# Build sans .dockerignore
docker build -t hello-dockerignore-front:noignore -f Dockerfile.front .
docker build -t hello-dockerignore-back:noignore -f Dockerfile.back .

# Build avec .dockerignore
docker build -t hello-dockerignore-front:ignore -f Dockerfile.front .
docker build -t hello-dockerignore-back:ignore -f Dockerfile.back .

# Build avec le Dockerfile.debug.dockerignore spécifique
docker build -t hello-dockerignore-back:debug -f Dockerfile.debug .

# Vérifier la taille des images
docker image ls hello-dockerignore-front
docker image ls hello-dockerignore-back

# Vérifier les fichiers présents dans l'image
docker run --rm hello-dockerignore-front:noignore ls -la /app/
docker run --rm hello-dockerignore-front:ignore ls -la /app/
docker run --rm hello-dockerignore:debug ls -la /app/.vscode/
```

### Bonus

* Mesurer la différence de temps de build avec et sans `.dockerignore` en utilisant `time docker build ...`
* Utiliser `docker image history` pour analyser les layers et leur taille
* Tester l'impact du `.dockerignore` sur l'invalidation du cache : modifier un fichier exclu (ex: `README.md`) et vérifier que le cache n'est pas invalidé

### Liens utiles

* [Documentation .dockerignore](https://docs.docker.com/build/concepts/context/#dockerignore-files)
* [Documentation BuildKit](https://docs.docker.com/build/buildkit/)
* [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)

---

[⬅️ 03-env-args](../../tree/03-env-args) ·
[📋 Sommaire](../../tree/main) ·
[05-troubleshooting ➡️](../../tree/05-troubleshooting)

💡 [Voir la solution](../../tree/04-dockerignore--solution)
