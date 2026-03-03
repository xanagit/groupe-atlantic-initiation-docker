# Sécurité : passer des secrets au build

[⬅️ 06-securite-non-root](../../tree/06-securite-non-root) ·
[📋 Sommaire](../../tree/main) ·
[08-optimisation-stages ➡️](../../tree/08-optimisation-stages)

💡 [Voir la solution](../../tree/07-securite-secrets--solution)

---

## Pourquoi ne pas utiliser `ARG` ou `ENV` pour les secrets ?

Lors de la construction d'une image `Docker`, les secrets (tokens d'accès, mots de passe, clés API) sont souvent passés en utilisant les instructions `ARG` ou `ENV`. Cette pratique est pourtant risquée.

Chaque instruction d'un `Dockerfile` crée un nouveau layer dans l'image. Dans un build mono-stage, les valeurs passées via `ARG` sont associées aux métadonnées de ces layers et sont visibles en clair via la commande `docker history` :

```bash
docker history --no-trunc mon-image
```

Même si le secret est "supprimé" dans une instruction `RUN` suivante, il reste accessible dans les layers précédents. L'image Docker est immuable : ses layers ne peuvent pas être modifiés après coup. Exemple :

```dockerfile
# Anti-pattern : le secret est visible dans docker history
ARG API_KEY

RUN echo "Utilisation de la clé : $API_KEY"
RUN unset API_KEY  # ❌ Inutile : le layer précédent contient toujours la valeur
```

Il est encore plus dangereux d'utiliser les instructions `ENV` car elles persistent dans l'image finale et sont visibles via `docker inspect`.

### La nuance du build multi-stage

Dans un build multi-stage, seuls les layers du stage final composent l'image. Un `ARG` utilisé uniquement dans un stage intermédiaire n'apparaîtra donc pas dans `docker history` de l'image finale. Cela peut donner un faux sentiment de sécurité, mais le secret reste exposé :

* dans les logs de build visibles en clair avec `--progress=plain` (ex. : pipelines CI/CD)
* dans le cache BuildKit local (`~/.docker/buildx/...`), accessible sur la machine de build

Un `ARG` placé dans le stage final, lui, est directement visible dans `docker history` de l'image.

### Les risques

| Méthode                              | Visible dans `docker history` (stage final) | Visible dans les logs de build | Recommandé |
| ------------------------------------ | ------------------------------------------- | ------------------------------ | ---------- |
| `ARG SECRET` (stage final)           | ❌ Oui                                      | ❌ Oui                         | ❌         |
| `ARG SECRET` (stage intermédiaire)   | ✅ Non                                      | ❌ Oui                         | ❌         |
| `ENV SECRET=valeur`                  | ❌ Oui                                      | ❌ Oui                         | ❌         |
| `COPY .env .`                        | ❌ Oui (contenu copié)                      | ❌ Oui                         | ❌         |
| `--mount=type=secret`                | ✅ Non                                      | ✅ Non                         | ✅         |

### La solution : `--mount=type=secret`

`Docker BuildKit` est un moteur de build nouvelle génération pour `Docker` introduit à partir de `Docker 18.09` et devenu le builder par défaut depuis `Docker 23.0`. Outre la parallélisation et une optimisation du cache, il introduit les montages secrets (`--mount=type=secret`). Cette fonctionnalité permet d'accéder à un secret uniquement pendant l'exécution d'une instruction `RUN`, sans que ce secret ne soit jamais stocké dans un layer de l'image.

Le secret est monté en lecture seule dans un système de fichiers temporaire sous `/run/secrets/<id>`. Une fois l'instruction terminée, le fichier disparaît sans laisser de trace.

Syntaxe dans le Dockerfile :

```dockerfile
RUN --mount=type=secret,id=mon_secret \
    MON_SECRET=$(cat /run/secrets/mon_secret) && \
    echo "Secret utilisé, mais pas stocké !"
```

Commande de build associée :

```bash
# Passer le secret depuis un fichier
echo "mon-super-secret" > mon_fichier_secret
docker build --secret id=mon_secret,src=./mon_fichier_secret .

# Passer le secret depuis une variable d'environnement
docker build --secret id=mon_secret,env=MA_VARIABLE_ENV .
```

> Pour les versions entre `Docker 18.09` et `Docker 23`, il faut spécifier l'utilisation de buildkit : `DOCKER_BUILDKIT=1 docker build ...`.

### Les options de `--mount=type=secret`

| Option     | Description                                                            | Exemple                   |
| ---------- | ---------------------------------------------------------------------- | ------------------------- |
| `id`       | Identifiant du secret dans le Dockerfile                               | `id=api_key`              |
| `src`      | Chemin vers le fichier secret sur la machine hôte                      | `src=./api_key`           |
| `env`      | Variable d'environnement source                                        | `env=API_KEY`             |
| `target`   | Chemin de montage dans le conteneur (par défaut : `/run/secrets/<id>`) | `target=/run/secrets/key` |
| `required` | Échoue si le secret n'est pas fourni (par défaut : `false`)            | `required=true`           |

> **Bonne pratique** : ne jamais stocker de secrets de runtime dans l'image. Les passer au conteneur au démarrage via des variables d'environnement ou des volumes secrets.

## Mise en pratique

### But

1. Vérifier qu'un secret passé via `ARG` est visible dans `docker history`
2. Utiliser `--mount=type=secret` pour passer un secret de manière sécurisée
3. Vérifier qu'aucune trace du secret n'apparaît dans l'image construite

### L'application

L'application reprend l'API web `ASP.NET Core 8.0` des exercices précédents. Pendant la construction, elle simule l'utilisation d'un token d'accès à un repository privé. Ce token est nécessaire au build mais ne doit jamais apparaître dans l'image finale.

Endpoints exposés :

* `GET /` : JSON avec le titre et un message de confirmation
* `GET /health` : JSON `{ "status": "up" }`

### Prérequis — Créer le fichier secret

Créer un fichier `secret` contenant un faux token (ce fichier est dans `.gitignore`) :

```bash
echo "mon-super-token-secret-12345" > secret
```

> Ce fichier ne doit jamais être commité dans Git. Vérifier qu'il est bien listé dans `.gitignore`. Un fichier `secret.expl` est fourni comme modèle.

### Étape 1 — Vérifier la fuite de secrets avec `ARG`

Construire l'image avec le `Dockerfile.insecure` en passant le token via un argument de build :

```bash
docker build \
  --build-arg API_KEY=$(cat secret) \
  -t hello-secrets:insecure \
  -f Dockerfile.insecure \
  .
```

Inspecter l'historique de l'image pour retrouver le token :

```bash
# Afficher l'historique complet (sans troncature)
docker history --no-trunc hello-secrets:insecure

# Rechercher spécifiquement la clé
docker history hello-secrets:insecure | grep -i api_key
```

> Le token est visible en clair dans l'historique de l'image, dans la ligne correspondant à l'instruction `RUN` qui l'utilise. N'importe quelle personne ayant accès à l'image peut récupérer le secret.

### Étape 2 — Sécuriser le secret avec `--mount=type=secret`

Modifier le fichier `Dockerfile.secrets` pour :

1. Supprimer l'instruction `ARG API_KEY`
2. Ajouter `--mount=type=secret,id=api_key` à l'instruction `RUN`
3. Lire le secret depuis `/run/secrets/api_key` dans le shell

Construire l'image en passant le secret de manière sécurisée :

```bash
docker build \
  --secret id=api_key,src=secret \
  -t hello-secrets:secure \
  -f Dockerfile.secrets \
  .
```

### Etape 3 - Vérifier que le secret n'apparaît plus dans l'historique

```bash
# Comparer les deux historiques
docker history hello-secrets:insecure | grep -i api_key
docker history hello-secrets:secure | grep -i api_key
```

Vérifier que l'application fonctionne :

```bash
# Lancer le conteneur sécurisé
docker run -d -p 8080:8080 hello-secrets:secure

# Tester l'API
curl -s http://localhost:8080 | jq
curl -s http://localhost:8080/health | jq
```

### Validation

* [ ] `docker build` se termine sans erreur pour les deux Dockerfiles
* [ ] `docker history hello-secrets:insecure` affiche le token en clair dans une ligne `ARG`
* [ ] `docker history hello-secrets:secure` n'affiche aucune trace du token
* [ ] `curl -s http://localhost:8080` retourne un JSON

### Commandes de build & run

```bash
# Build insecure
docker build \
  --build-arg API_KEY=$(cat secret) \
  -t hello-secrets:insecure \
  -f Dockerfile.insecure \
  .

# Build secure (--mount=type=secret)
docker build \
  --secret id=api_key,src=secret \
  -t hello-secrets:secure \
  -f Dockerfile.secrets \
  .

# Lancer les conteneurs
docker run -d -p 8080:8080 --name secrets-insecure hello-secrets:insecure
docker run -d -p 8080:8080 --name secrets-secure hello-secrets:secure
```

Commandes utiles :

```bash
# Inspecter l'historique des images
docker history hello-secrets:insecure
docker history hello-secrets:secure

# Tester l'API
curl -s http://localhost:8080 | jq
curl -s http://localhost:8080/health | jq

# Arrêter et supprimer les conteneurs
docker stop secrets-insecure secrets-secure
docker rm secrets-insecure secrets-secure
```

### Bonus

* Passer le secret depuis une variable d'environnement au lieu d'un fichier : `docker build --secret id=api_key,env=API_KEY .`
* Ajouter l'option `required=true` au montage secret et observer le comportement si le secret n'est pas fourni

### Liens utiles

* [Documentation --mount=type=secret](https://docs.docker.com/build/building/secrets/)
* [Documentation BuildKit](https://docs.docker.com/build/buildkit/)
* [Bonnes pratiques de sécurité Docker](https://docs.docker.com/build/building/best-practices/#secrets)
* [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)

---

[⬅️ 06-securite-non-root](../../tree/06-securite-non-root) ·
[📋 Sommaire](../../tree/main) ·
[08-optimisation-stages ➡️](../../tree/08-optimisation-stages)

💡 [Voir la solution](../../tree/07-securite-secrets--solution)
