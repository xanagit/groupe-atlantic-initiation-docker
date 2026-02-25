# Les instructions `ENV` et `ARG`

[⬅️ 02-multi-stage](../../tree/02-multi-stage) ·
[📋 Sommaire](../../tree/main) ·
[04-dockerignore ➡️](../../tree/04-dockerignore)

[💡 Voir la solution](../../tree/03-env-args--solution)

---

## Pourquoi `ENV` et `ARG` ?

Un des principes des [12-Factor Apps](https://12factor.net/fr/config) (Build once, deploy everywhere), préconise que la configuration d'une application ne doit pas nécessiter la reconstruction de l'application entière à chaque modification.

Pour répondre à cette problématique, `Docker` fournit deux mécanismes complémentaires :

* `ARG` : variable disponible uniquement au moment du build (`docker build`). Elle n'existe plus dans le conteneur au runtime.
* `ENV` : variable d'environnement disponible au runtime dans le conteneur. Elle peut être lue par l'application.

### Différences clés

| Critère                     | `ARG`                                     | `ENV`                                          |
| --------------------------- | ----------------------------------------- | ---------------------------------------------- |
| Disponibilité               | Build-time uniquement                     | Runtime (et build-time)                        |
| Override                    | `docker build --build-arg`                | `docker run -e`                                |
| Visible dans l'image finale | ❌ Non                                    | ✅ Oui                                         |
| Cas d'usage typique         | Version SDK, configuration de compilation | Configuration applicative, URLs, feature flags |

### Syntaxe dans le Dockerfile

```dockerfile
# ARG avec valeur par défaut
ARG SDK_VERSION=8.0
# Utilisation dans FROM
FROM mcr.microsoft.com/dotnet/sdk:${SDK_VERSION} AS build

# ENV avec valeur par défaut
ENV APP_ENVIRONMENT=Production
```

### Override à l'exécution

```bash
# Override d'un ARG au build
docker build --build-arg SDK_VERSION=9.0 -t myapp .

# Override d'un ENV au run
docker run -e APP_ENVIRONMENT=Staging myapp
```

> **Point clé** : un `ARG` déclaré avant un `FROM` est utilisable dans l'instruction `FROM`, mais pas dans les stages suivants. La disponibilité d'un `ARG` est limitée au stage dans lequel il est déclaré. `Env` a le même comportement même s'il persiste au runtime.

### Le principe Build Once, Deploy Everywhere

L'idée est de construire **une seule image** et de la déployer sur tous les environnements (dev, staging, production) en ne changeant que les variables d'environnement :

* Build Once : `docker build -t myapp .`
* Deploy everywhere :
  * dev : `docker run -e APP_ENVIRONMENT=Development myapp`
  * preprod :  `docker run -e APP_ENVIRONMENT=Preprod myapp`
  * production : `docker run -e APP_ENVIRONMENT=Production myapp`

## Mise en pratique

### But

Adapter l'application et le Dockerfile multi-stage de l'exercice précédent pour :

1. Paramétrer le build en utilisant des `ARG` (version du SDK/runtime, configuration de build)
2. Rendre le comportement de l'application configurable au runtime en utilisant `ENV`
3. Tester le principe `build once, deploy everywhere`

### L'application

L'application reprend l'API web de la partie `02-multi-stage` mais le `Program.cs` doit être modifié pour lire la configuration depuis les variables d'environnement et les exposer dans la réponse JSON du endpoint `/`.

Les variables d'environnement attendues par l'application :

| Variable           | Description                        | Valeur par défaut   |
| ------------------ | ---------------------------------- | ------------------- |
| `APP_ENVIRONMENT`  | Nom de l'environnement d'exécution | `Production`        |
| `APP_TITLE`        | Titre affiché dans la réponse JSON | `Hello ENV & ARG !` |

Le endpoint `/` doit retourner un JSON de la forme :

```json
{
  "title": "<valeur de APP_TITLE>",
  "environment": "<valeur de APP_ENVIRONMENT>",
  "message": "Le endpoint / fonctionne correctement !"
}
```

### Etape 1 — Paramétrer le build en utilisant des `ARG`

Utiliser le Dockerfile `Dockerfile.base` et ajouter des `ARG` pour le paramétrer :

1. **`DOTNET_VERSION`** : version du SDK et du runtime .NET (valeur par défaut : `8.0`)
2. **`BUILD_CONFIGURATION`** : configuration de compilation `Release` ou `Debug` (valeur par défaut : `Release`)

> L'argument `DOTNET_VERSION` doit être déclaré avant le premier `FROM` pour être utilisable par l'instruction `FROM`.

### Etape 2 — Rendre le comportement de l'application configurable au runtime en utilisant `ENV`

#### Modifier le `Program.cs`

Modifier `Program.cs` pour qu'il lise les variables d'environnement `APP_ENVIRONMENT` et `APP_TITLE` et les retourne dans la réponse JSON du endpoint `/`.

> Utiliser `Environment.GetEnvironmentVariable("MA_VARIABLE")` pour lire les variables d'environnement depuis le code.
> Utiliser l'opérateur `??` pour définir une valeur par défaut : `Environment.GetEnvironmentVariable("MA_VARIABLE") ?? "valeur par défaut"`.

#### Ajouter les `ENV` dans le Dockerfile

Ajouter dans le stage `runtime` les variables d'environnement avec des valeurs par défaut :

* `APP_ENVIRONMENT` = `Production`
* `APP_TITLE` = `Hello ENV & ARG !`

### Etape 3 - Tester le principe `build once, deploy everywhere`

Lancer l'application plusieurs fois en modifiant successivement les variables d'environnement et en testant la modification du comportement de l'application :

* 1er run : valeurs par défaut
* 2e run :
  * `APP_ENVIRONMENT` = `Dev`
* 3e run :
  * `APP_ENVIRONMENT` = `Preprod`
  * `APP_TITLE` = `API de preprod`

### Validation

* [ ] `docker build` se termine sans erreur
* [ ] `docker run -p 8080:8080 hello-env-arg` démarre le conteneur
* [ ] `curl -s http://localhost:8080` retourne le JSON avec l'environnement `Production` et le titre `Hello ENV & ARG !`
* [ ] `docker run -p 8080:8080 -e APP_ENVIRONMENT=Preprod -e APP_TITLE="API de preprod"` retourne le JSON avec `Preprod` et `API de preprod`
* [ ] `docker build --build-arg BUILD_CONFIGURATION=Debug` produit un build en mode Debug

### Commandes de build & run

```bash
# Construire l'image avec les valeurs par défaut
docker build -t hello-env-arg:base -f Dockerfile.base .

# Lancer avec les valeurs par défaut
docker run -p 8080:8080 hello-env-arg:base

# Tester
curl -s http://localhost:8080 | jq
# { "title": "Hello ENV & ARG !", "environment": "Production", "message": "..." }
```

Surcharge de `ENV` au runtime :

```bash
# Simuler un déploiement en Preprod
docker run -p 8080:8080 \
  -e APP_ENVIRONMENT=Preprod \
  -e APP_TITLE="API de preprod" \
  hello-env-arg:base

curl -s http://localhost:8080 | jq
# { "title": "API de preprod", "environment": "Preprod", "message": "..." }
```

Surcharge de `ARG` au build :

```bash
# Builder en mode Debug
docker build --build-arg BUILD_CONFIGURATION=Debug -t hello-env-arg:debug -f Dockerfile.base .

# Builder avec une autre version de .NET
docker build --build-arg DOTNET_VERSION=9.0 -t hello-env-arg:net9 -f Dockerfile.base .
```

### Bonus

* L'application est exposée sur le port `8080` par défaut. Trouver la variable d'environnement utilisée et la surcharger pour permettre l'écoute sur le port `8080` et `5000`
* Essayer d'utiliser un `ARG` au runtime (par exemple afficher `BUILD_CONFIGURATION` dans la réponse JSON) et observer le comportement du conteneur
* Inspecter le conteneur via `docker inspect` et trouver le chemin JSON d'accès aux variables d'environnement définies dans l'image

### Liens utiles

* [Documentation ARG](https://docs.docker.com/reference/dockerfile/#arg)
* [Documentation ENV](https://docs.docker.com/reference/dockerfile/#env)
* [12-Factor App : Configuration](https://12factor.net/fr/config)
* [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)

---

[⬅️ 02-multi-stage](../../tree/02-multi-stage) ·
[📋 Sommaire](../../tree/main) ·
[04-dockerignore ➡️](../../tree/04-dockerignore)

[💡 Voir la solution](../../tree/03-env-args--solution)
