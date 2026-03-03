# Sécurité : passer des secrets au build : solution

[⬅️ 06-securite-non-root](../../tree/06-securite-non-root) ·
[📋 Sommaire](../../tree/main) ·
[08-optimisation-stages ➡️](../../tree/08-optimisation-stages)

[📝 Retour à l'énoncé](../../tree/07-securite-secrets)

---

## Rappel de l'objectif

Vérifier qu'un secret passé via `ARG` est visible dans `docker history`, puis corriger `Dockerfile.secrets` pour utiliser `--mount=type=secret` afin que le secret ne laisse aucune trace dans l'image.

## Solution

Ecriture du fichier de secret :

```bash
echo "mon-super-token-secret-12345" > secret
```

### Étape 1 — Vérifier la fuite de secrets avec `ARG`

```bash
# Build insecure
docker build \
  --build-arg API_KEY=$(cat secret) \
  -t hello-secrets:insecure \
  -f Dockerfile.insecure \
  .
# 1 warning found (use docker --debug to expand):
# - SecretsUsedInArgOrEnv: Do not use ARG or ENV instructions for sensitive data (ARG "API_KEY") (line 10)

docker history hello-secrets:insecure | grep -i api_key
# <missing>      45 minutes ago   RUN |1 API_KEY=mon-super-token-secret-12345 …   4.1kB     buildkit.dockerfile.v0
# <missing>      45 minutes ago   ARG API_KEY=mon-super-token-secret-12345        0B        buildkit.dockerfile.v0
```

> La ligne `|1 API_KEY=mon-super-token-secret-12345` montre que `BuildKit` stocke le nom et la valeur des `ARG` dans les métadonnées du layer créée par la commande `RUN`.
> La valeur du secret est visible en clair : n'importe quelle personne ayant accès à l'image peut récupérer le token avec la commande  `docker history`.

### Étape 2 — Sécuriser le secret avec `--mount=type=secret`

#### `Dockerfile.secrets`

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /app
COPY . .
RUN dotnet restore
RUN dotnet publish --configuration Release -o /app/publish

# Le secret est accessible à /run/secrets/api_key uniquement pendant cette instruction RUN
# Il n'est jamais stocké dans un layer de l'image
RUN --mount=type=secret,id=api_key \
    API_KEY=$(cat /run/secrets/api_key) && \
    echo "Authentification réussie (clé : ***)" && \
    echo "Simulation d'accès au dépôt privé..."

# Le secret /run/secrets/api_key n'existe plus
RUN ls -ali /run

WORKDIR /app/publish
USER app
ENTRYPOINT ["dotnet", "HelloSecrets.dll"]
```

Modifications apportées par rapport au `Dockerfile.insecure` :

1. Suppression de l'instruction `ARG API_KEY`
2. Ajout de `--mount=type=secret,id=api_key sur l'instruction `RUN`

La variable `API_KEY` est assignée en lisant le fichier `/run/secrets/api_key`, monté temporairement par BuildKit. Une fois l'instruction `RUN` terminée, le fichier est démonté et aucune valeur n'est persistée dans le layer.

> Il est possible d'ajouter `required=true` pour faire échouer le build si le secret n'est pas fourni : `--mount=type=secret,id=api_key,required=true`.

#### Build sécurisé

```bash
# Build sécurisé
docker build \
  --secret id=api_key,src=secret \
  -t hello-secrets:secure \
  -f Dockerfile.secrets \
  --progress=plain \
  --no-cache .

# ...
#11 [build 7/8] RUN ls -ali /run
#11 0.084 total 12
#11 0.084 5304257 drwxr-xr-x 1 root root 4096 Mar  3 10:02 .
#11 0.084 5304258 drwxr-xr-x 1 root root 4096 Mar  3 10:02 ..
#11 0.084 1583312 drwxrwxrwt 2 root root 4096 Feb 23 00:00 lock
#11 DONE 0.1s
# ...
```

> Dans l'instruction suivante, on ne peut plus accéder au secret qui a été démonté.

#### Vérification : le secret n'est plus dans l'historique

```bash
docker history hello-secrets:insecure | grep -i api_key
# <missing>  |1 API_KEY=mon-super-token-secret-12345 ... 

docker history --no-trunc hello-secrets:secure | grep -i api_key
# <missing> ... API_KEY=$(cat /run/secrets/api_key) ...
```

Pour confirmer avec l'historique complet :

```bash
docker history --no-trunc hello-secrets:secure
```

> La ligne `RUN` du `Dockerfile.secrets` montre uniquement la commande `$(cat /run/secrets/api_key)` qui ne contient pas la valeur du secret, seulement l'instruction pour le lire. La valeur n'a jamais été écrite dans un layer.

### Bonus : Passer le secret depuis une variable d'environnement

Au lieu de lire le secret depuis un fichier, il est possible de le passer directement depuis une variable d'environnement de la machine hôte avec l'option `env` :

```bash
# Export variable d'environnement
export API_KEY="mon-super-token-secret-12345"

# Build secure
docker build \
  --secret id=api_key,env=API_KEY \
  -t hello-secrets:secure \
  -f Dockerfile.secrets \
  .
```

Le `Dockerfile.secrets` ne change pas : il lit toujours le secret depuis `/run/secrets/api_key`. C'est `BuildKit` qui se charge de monter la variable d'environnement comme un fichier secret temporaire.

> Cette approche est utile dans les pipelines CI/CD où les secrets sont injectés comme variables d'environnement (GitHub Actions, GitLab CI, Azure Pipelines...) plutôt que stockés dans des fichiers.

### Bonus : Comportement de `required=true` si le secret est absent

Tenter de builder `Dockerfile.secrets` sans fournir le secret :

```bash
# Build sans spécifier le secret
docker build \
  -t hello-secrets:secure \
  -f Dockerfile.secrets \
  --no-cache .

# ...
# > [build 6/8] RUN --mount=type=secret,id=api_key...":
# 0.101 cat: /run/secrets/api_key: No such file or directory
# ...
# ERROR: failed to build: failed to solve: process "/bin/sh -c API_KEY=$(cat /run/secrets/api_key) ... did not complete successfully: exit code: 1
```

> Sans `required=true`, le build se poursuit en silence, le fichier `/run/secrets/api_key` n'existe pas et la commande `cat` échoue avec une erreur peu explicite.

Ajout de `required=true` :

```dockerfile
RUN --mount=type=secret,id=api_key,required=true \
    API_KEY=$(cat /run/secrets/api_key) && \
    echo "Authentification réussie (clé : ***)" && \
    echo "Simulation d'accès au dépôt privé..."
```

L'erreur lors du build est maintenant plus explicite :

```bash
# Build sans spécifier le secret
docker build \
  -t hello-secrets:secure \
  -f Dockerfile.secrets-required \
  --no-cache .

# ...
# ERROR: failed to build: failed to solve: secret api_key: not found
```

## Récapitulatif des points abordés

| Bonne pratique                                     | Pourquoi                                                                                        |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Ne jamais passer un secret via `ARG`               | La valeur est stockée dans les métadonnées de l'image et visible via `docker history`           |
| Ne jamais passer un secret via `ENV`               | La valeur persiste dans l'image finale et est visible via `docker inspect`                      |
| Ne jamais copier un fichier `.env` dans l'image    | Son contenu se retrouve dans un layer et ne peut pas être effacé après coup                     |
| Utiliser `--mount=type=secret`                     | Le secret est accessible uniquement pendant le `RUN`, sans jamais être écrit dans un layer      |
| Ajouter `required=true`                            | Le build échoue explicitement si le secret est absent, plutôt que de continuer silencieusement  |
| Ajouter le fichier secret dans `.gitignore`        | Évite de commiter accidentellement le secret dans le dépôt Git                                  |
| Ajouter le fichier secret dans `.dockerignore`     | Évite d'inclure le secret dans le build context (même si `--mount` ne le copie pas)             |

---

[⬅️ 06-securite-non-root](../../tree/06-securite-non-root) ·
[📋 Sommaire](../../tree/main) ·
[08-optimisation-stages ➡️](../../tree/08-optimisation-stages)

[📝 Retour à l'énoncé](../../tree/07-securite-secrets)
