# Les instructions `ENV` et `ARG` : solution

[⬅️ 02-multi-stage](../../tree/02-multi-stage) ·
[📋 Sommaire](../../tree/main) ·
[04-dockerignore ➡️](../../tree/04-dockerignore)

[📝 Retour à l'énoncé](../../tree/03-env-args)

---

## Rappel de l'objectif

Adapter l'application et le Dockerfile multi-stage pour paramétrer le build via des `ARG` et rendre le comportement configurable au runtime via des `ENV`, en démontrant le principe build once, deploy everywhere.

## Solution

### Etape 1 — Paramétrer le build en utilisant des `ARG`

```dockerfile
# -- ARG déclaré avant FROM
ARG DOTNET_VERSION=8.0

# ---------- Stage 1 : Build ----------
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS build

# Déclaration après le FROM pour utilisation dans le stage
ARG BUILD_CONFIGURATION=Release

WORKDIR /src

...

# Publish en utilisant BUILD_CONFIGURATION
RUN dotnet publish --configuration ${BUILD_CONFIGURATION} -o /app/publish --no-restore

# ---------- Stage 2 : Runtime ----------
FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION} AS runtime

...
```

> `DOTNET_VERSION` est déclaré avant le premier `FROM` : il est disponible dans les instructions `FROM` elles-mêmes mais pas dans les instructions du stage sauf s'il est re-déclaré à l'intérieur du stage.
>
> `BUILD_CONFIGURATION` déclaré après un `FROM` : il est disponible uniquement dans ce stage et n'est pas conservé dans l'image finale.

### Etape 2 — Rendre le comportement de l'application configurable au runtime en utilisant `ENV`

#### Modifier le `Program.cs`

```csharp
...

var appEnvironment = Environment.GetEnvironmentVariable("APP_ENVIRONMENT") ?? "Production";
var appTitle = Environment.GetEnvironmentVariable("APP_TITLE") ?? "Hello ENV & ARG !";

app.MapGet("/", () => Results.Json(...));

...
```

#### Ajouter les `ENV` dans le Dockerfile

```dockerfile
...

# ---------- Stage 2 : Runtime ----------
FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION} AS runtime

# Variables d'environnements avec leur valeur par défaut
ENV APP_ENVIRONMENT=Production
ENV APP_TITLE="Hello ENV & ARG !"

...
```

`APP_ENVIRONMENT` et `APP_TITLE` sont :

* Persistées dans l'image
* Disponibles au runtime (lecture via `Environment.GetEnvironmentVariable()`)
* Surchargeables sans reconstruire l'image (`docker run -e`)

### Etape 3 - Tester le principe `build once, deploy everywhere`

#### Build once

Build simple :

```bash
# Build unique de l'image
docker build -t hello-env-args:base -f Dockerfile.base .
```

Surcharge des `ARG` au build :

```bash
# Builder avec .NET 9.0 (modification de TargetFramework dans le csproj nécessaire)
docker build --build-arg DOTNET_VERSION=9.0 -t hello-env-args:net9 -f Dockerfile.net9 .

# Builder en mode Debug
docker build --build-arg BUILD_CONFIGURATION=Debug -t hello-env-args:debug -f Dockerfile.base .

# Combiner les deux
docker build \
  --build-arg DOTNET_VERSION=9.0 \
  --build-arg BUILD_CONFIGURATION=Debug \
  -t hello-env-args:net9-debug \
  -f Dockerfile.net9 .
```

#### Deploy everywhere

##### 1er run : valeurs par défaut

```bash
# Run
docker run -d -p 8080:8080 hello-env-args:base

# Test
curl -s http://localhost:8080
# {"title":"Hello ENV & ARG !","environment":"Production","message":"Le endpoint / fonctionne correctement !"}
```

##### 2e run : `APP_ENVIRONMENT`=`Dev`

```bash
# Run
docker run -d -p 8080:8080 \
  -e APP_ENVIRONMENT=Dev \
  hello-env-args:base

# Test
curl -s http://localhost:8080
# {"title":"Hello ENV & ARG !","environment":"Dev","message":"Le endpoint / fonctionne correctement !"}
```

##### 3e run : `APP_ENVIRONMENT`=`Preprod` & `APP_TITLE`=`API de preprod`

```bash
# Run
docker run -d -p 8080:8080 \
  -e APP_ENVIRONMENT=Preprod \
  -e APP_TITLE="API de preprod" \
  hello-env-args:base

# Test
curl -s http://localhost:8080
# {"title":"API de preprod","environment":"Preprod","message":"Le endpoint / fonctionne correctement !"}
```

### Bonus : Inspecter le conteneur

La commande `docker inspect` retourne l'ensemble des métadata d'un conteneur ou d'une image au format JSON.
Les variables d'environnement se trouvent dans le chemin `.[].Config.Env` :

```bash
# Inspecter l'image
docker inspect hello-env-args:base | jq '.[].Config.Env'
# [
#   "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
#   "ASPNETCORE_HTTP_PORTS=8080",
#   "DOTNET_RUNNING_IN_CONTAINER=true",
#   "APP_ENVIRONMENT=Production",
#   "APP_TITLE=Hello ENV & ARG !"
# ]
```

### Bonus : écoute sur les ports `8080` et `5000`

L'image `mcr.microsoft.com/dotnet/aspnet:8.0` spécifie la variable d'environnement `ASPNETCORE_HTTP_PORTS` pour configurer le port d'écoute.
Pour vérifier la valeur par défaut, il est possible de vérifier `.[].Config.Env` lors d'un inspect de l'image :

```bash
docker inspect hello-env-args:base | jq '.[].Config.Env'
# [
#   "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
#   "ASPNETCORE_HTTP_PORTS=8080",
#   "DOTNET_RUNNING_IN_CONTAINER=true",
#   "APP_ENVIRONMENT=Production",
#   "APP_TITLE=Hello ENV & ARG !"
# ]
```

La surcharge se fait comme pour un `ENV` défini dans le Dockerfile. Pour spécifier de multiples ports, il faut les séparer par des `;` :

```bash
# Le port 5000 est utilisé par Airdrop sur Mac s'il est activé (utiliser un autre port)
# Vérifier si le port est déjà en cours d'utilisation
lsof -i :5000
# Démarrage en surchargent ASPNETCORE_HTTP_PORTS et mappant les ports
docker run -d -p 5050:5000 -p 8080:8080 -e ASPNETCORE_HTTP_PORTS="8080;5000" hello-env-args:base

# Test sur le port 8080
curl -s http://localhost:8080
# {"title": "Hello ENV & ARG !", "environment": "Production", "message": "Le endpoint / fonctionne correctement !"}

# Test sur le port 5000
curl -s http://localhost:5000
# {"title": "Hello ENV & ARG !", "environment": "Production", "message": "Le endpoint / fonctionne correctement !"}
```

### Bonus : `ARG` au runtime

Si on essaie de lire un `ARG` au runtime , on récupérera une valeur nulle car ARG n'existe qu'au moment du build :

```csharp
// buildConfig = null car l'ARG BUILD_CONFIGURATION n'existe pas au runtime
var buildConfig = Environment.GetEnvironmentVariable("BUILD_CONFIGURATION");
```

## Récapitulatif des points abordés

| Bonne pratique                   | Pourquoi                                                             |
| -------------------------------- | -------------------------------------------------------------------- |
| `ARG` pour le build              | Paramétrer les versions et la compilation sans changer le Dockerfile |
| `ENV` pour le runtime            | Configurer l'application sans reconstruire l'image                   |
| `ARG` avant `FROM`               | Permet de paramétrer l'image de base                                 |
| Build Once, Deploy Everywhere    | Une seule image pour tous les environnements                         |
| Ne pas hardcoder la config       | Principe 12-Factor : la config vient de l'environnement pas du build |
| `docker inspect` pour les `ENV`  | Vérifier les variables présentes dans l'image                        |

---

[⬅️ 02-multi-stage](../../tree/02-multi-stage) ·
[📋 Sommaire](../../tree/main) ·
[04-dockerignore ➡️](../../tree/04-dockerignore)

[📝 Retour à l'énoncé](../../tree/03-env-args)
