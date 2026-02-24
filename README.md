# Rappels des concepts Docker vu lors du RETEX

---

## Navigation

---

⬅️ [00-rappels](../../tree/00-rappels)

📋 [Sommaire](../../tree/main)

➡️ [02-multi-stage](../../tree/02-multi-stage)

💡 [Voir la solution](../../tree/01-dockerisation-simple--solution)

---

## Fonctionnement de Docker

Docker repose sur une architecture client-serveur :

- **Docker Daemon** (`dockerd`) : gère les objets Docker (images, conteneurs, réseaux, volumes)
- **Docker Client** (`docker`) : interface CLI qui communique avec le daemon via l'API REST
- **Registry** : dépôt d'images (Docker Hub, Azure Container Registry, GitHub Container Registry…)

### Concepts clés

- **Image** : template non-modifiable composé de multiples layers empilées
- **Conteneur** : instance d'exécution d'une image (ajoute une couche R/W éphémère à l'image)
- **Layer** : certaines instructions (`RUN`, `COPY` / `ADD`) du Dockerfile créent un layer ; les layers sont mis en cache et partagés entre images
- **Tag** : étiquette versionnée d'une image (`myapp:1.2.0`, `myapp:latest`)

#### Instructions essentielles du Dockerfile

| Instruction    | Rôle                                                |
| -------------- | --------------------------------------------------- |
| `FROM`         | Sélectionne l'image de base                         |
| `WORKDIR`      | Position le répertoire de travail dans le conteneur |
| `COPY` / `ADD` | Copie les fichiers dans l'image (crée une layer)    |
| `RUN`          | Exécute une commande (crée une layer)               |
| `ENV`          | Définit une variable d'environnement                |
| `ARG`          | Définit un argument de build                        |
| `EXPOSE`       | Documente le port exposé                            |
| `ENTRYPOINT`   | Point d'entrée fixe du conteneur                    |
| `CMD`          | Commande par défaut au démarrage                    |

> **`CMD` vs `ENTRYPOINT`** : `ENTRYPOINT` définit le binaire à exécuter, `CMD` fournit les arguments par défaut.

## Mise en pratique

## But

Conteneuriser l'application Node.js présente dans cette branche afin de la rendre exécutable dans un conteneur Docker.

### Application

L'application consiste en un serveur HTTP simple (Express) qui écoute sur le port `3000`
et répond `Hello Docker!` sur la route `/`.

Pour la lancer localement (sans Docker) :

```bash
npm install
npm run serve / node server.js
```

## Actions à réaliser

Créer un fichier `Dockerfile` à la racine du projet qui :

1. Utiliser l'image de base node 25 (rechercher sur Docker Hub)
2. Définir `/app` comme répertoire de travail
3. Copier les fichiers de dépendances (`package.json`, `package-lock.json`)
4. Installer les dépendances en utilisant `npm ci` pour se baser exactement sur le fichier `package-lock.json`
5. Copier le code source
6. Exposer le port `3000`
7. Définir la commande de démarrage

### Validation

- [ ] `docker build` se termine sans erreur
- [ ] `docker run -p 3000:3000 hello-docker` démarre le conteneur
- [ ] `curl http://localhost:3000` retourne le json contenant les message hello Docker.

### Commandes de build & run

Commandes de construction et lancement :

```bash
# Construire l'image
docker build -t hello-docker .

# Lancer le conteneur
docker run -p 3000:3000 hello-docker
# Lancer le conteneur en mode detached
docker run -p 3000:3000 -d hello-docker
# Lancer le conteneur en mode detached en le nommant
docker run -p 3000:3000 -d --name hello hello-docker
```

Autres commandes :

```bash
# Lister les images
docker image ls
# Lister les conteneurs
docker ps
# Lister tous les conteneurs
docker ps -a
# Supprimer un conteneur
docker rm <ID conteneur>
```

### Bonus

- Utiliser une image plus légère que l'image de base Node.js 25
- Ajouter un `HEALTHCHECK` dans le Dockerfile pour permettre à Dokcer de vérifier le status et inspecter le health check :

  ```bash
  # Vérification du Health State
  docker inspect <ID conteneur> | jq '.[].State.Health'
  # Ou
  docker inspect --format='{{json .State.Health}}' <ID conteneur> | jq
  ```

- Supprimer alternativement les interceptions `SIGINT` et `SIGTERM` et étudier la modification du comportement d'arrêt du conteneur

### Liens utiles

- [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)
- [Images Node.js sur Docker Hub](https://hub.docker.com/_/node)
