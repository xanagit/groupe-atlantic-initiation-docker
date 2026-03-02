# Sécurité : exécuter un conteneur en non-root

[⬅️ 05-troubleshooting](../../tree/05-troubleshooting) ·
[📋 Sommaire](../../tree/main) ·
[07-securite-secrets ➡️](../../tree/07-securite-secrets)

💡 [Voir la solution](../../tree/06-securite-non-root--solution)

---

## Pourquoi ne pas exécuter un conteneur en root ?

Par défaut, un conteneur `Docker` s'exécute avec l'utilisateur `root` (UID 0). Cela signifie que le processus principal du conteneur dispose de tous les privilèges d'administration à l'intérieur du conteneur.

Si une faille de sécurité est exploitée dans l'application (injection de commande, exécution de code arbitraire, ...), l'attaquant obtient immédiatement un accès root dans le conteneur. Combiné à une vulnérabilité d'évasion de conteneur (_container escape_), il peut potentiellement compromettre la machine hôte.

Le principe de moindre privilège (`least privilege`) recommande de n'accorder à un processus que les permissions strictement nécessaires à son fonctionnement. Exécuter un conteneur en non-root réduit la surface d'attaque et limite les dégâts en cas de compromission.

### Les risques

| Critère                      | En root (par défaut)                                             | En non-root                                             |
| ---------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------- |
| Accès au système de fichiers | Lecture / écriture sur tous les fichiers du conteneur            | Limité aux fichiers dont l'utilisateur est propriétaire |
| Impact d'une compromission   | Accès total au conteneur, risque d'évasion                       | Accès restreint, dégâts limités                         |
| Conformité Kubernetes        | Bloqué par les `SecurityContext` et les `Pod Security Standards` | ✅ Compatible                                           |
| Bonnes pratiques             | ❌ Déconseillé en production                                     | ✅ Recommandé                                           |

> **Point clé** : la plupart des orchestrateurs de conteneurs comme Kubernetes imposent ou recommandent fortement l'exécution en non-root via des politiques de sécurité. Adopter cette pratique dès le développement évite les mauvaises surprises au déploiement.

### L'instruction `USER`

L'instruction `USER` dans un Dockerfile définit l'utilisateur sous lequel les instructions suivantes (`RUN`, `CMD`, `ENTRYPOINT`) sont exécutées. Elle s'applique aussi au conteneur au runtime.

```dockerfile
# Par nom d'utilisateur
USER appuser

# Par UID
USER 1001
```

> **Attention** : l'instruction `USER` ne crée pas l'utilisateur. Il faut le créer au préalable avec `RUN` avant de pouvoir l'utiliser.

### Création d'un utilisateur dans un Dockerfile

La création d'un utilisateur dépend de la distribution de l'image de base.

**Images basées sur Debian/Ubuntu** (cas des images `mcr.microsoft.com/dotnet/aspnet:8.0`) :

```dockerfile
RUN groupadd -r appgroup && useradd -r -g appgroup -s /bin/false appuser
```

**Images basées sur Alpine** :

```dockerfile
RUN addgroup -S appgroup && adduser -S -G appgroup -s /bin/false appuser
```

Les options de la commande `useradd` :

* `-r` / `-S` : Crée un utilisateur/groupe système (sans répertoire home inutile)
* `-g` / `-G` : Spécifie le groupe principal
* `-s /bin/false` : Désactive le shell de login (sécurité supplémentaire)

### L'option `--chown` de `COPY`

Par défaut, les fichiers copiés avec `COPY` appartiennent à `root:root`. Il est préférable de changer le propriétaire des fichiers lors de la copie en utilisant l'option `--chown` de l'instruction `COPY`. Cela permet de spécifier le propriétaire directement lors de la copie, sans créer de layer supplémentaire :

```dockerfile
COPY --from=build --chown=appuser:appgroup /app/publish .
```

> **Bonne pratique** : il est préférable d'utiliser directement `COPY --chown` au lieu de `RUN chown -R` après une commande de copie. L'instruction `RUN chown` crée une layer supplémentaire qui duplique les fichiers.

### L'utilisateur intégré dans les images .NET 8+

Depuis `.NET 8`, Microsoft fournit un utilisateur non-root prêt à l'emploi dans ses images Docker :

* **Nom** : `app`
* **UID** : `1654`
* **Variable d'environnement** : `APP_UID=1654`

Cela permet de simplifier la mise en place :

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build --chown=app /app/publish .
USER app
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

> **Point clé** : utiliser l'utilisateur intégré `app` est la méthode recommandée pour les applications `.NET 8+`. Pour les autres langages, il faut créer l'utilisateur manuellement.

## Mise en pratique

### But

1. Observer qu'un conteneur s'exécute par défaut en `root`
2. Modifier un Dockerfile pour créer un utilisateur non-root et exécuter l'application avec celui-ci
3. Utiliser l'utilisateur intégré des images `.NET 8+`

### L'application

L'application reprend l'API web `ASP.NET Core 8.0` des exercices précédents. Le endpoint `/` retourne un JSON qui inclut le nom de l'utilisateur exécutant le processus, ce qui permet de vérifier visuellement si le conteneur tourne en root ou non.

Endpoints exposés :

* `GET /` : JSON avec le titre, l'utilisateur du processus et un message
* `GET /health` : JSON `{ "status": "up" }`

### Étape 1 — Observer qu'un conteneur s'exécute par défaut en `root`

Construire et lancer le conteneur à partir du `Dockerfile.root` :

```bash
# Construire l'image
docker build -t hello-nonroot:root -f Dockerfile.root .

# Lancer le conteneur
docker run -d -p 8080:8080 --name nonroot-test hello-nonroot:root
```

Vérifier quel utilisateur exécute le processus dans le conteneur :

```bash
# Via l'API
curl -s http://localhost:8080 | jq

# Via docker exec
docker exec nonroot-test whoami
docker exec nonroot-test id
```

> 💡 Le endpoint `/` affiche `"user": "root"` et la commande `whoami` retourne `root`. Le processus tourne avec les privilèges les plus élevés.

Observer les permissions sur les fichiers de l'application :

```bash
docker exec nonroot-test ls -la /app
```

### Étape 2 — Créer un utilisateur non-root

Modifier le fichier `Dockerfile.nonroot` pour :

1. Créer un utilisateur `appuser` sans shell de login
2. Copier les fichiers avec le bon propriétaire en utilisant l'option `--chown` de `COPY`
3. Demander à l'image d'utiliser `appuser` comme utilisateur avec l'instruction `USER`

> L'image `mcr.microsoft.com/dotnet/aspnet:8.0` est basée sur Debian : utiliser la commande `useradd`.

Construire et lancer le conteneur :

```bash
# Construire l'image
docker build -t hello-nonroot:nonroot -f Dockerfile.nonroot .

# Lancer le conteneur
docker run -d -p 8080:8080 --name nonroot-nonroot hello-nonroot:nonroot
```

Vérifier que le processus ne tourne plus en root :

```bash
# Via l'API
curl -s http://localhost:8080 | jq

# Via docker exec
docker exec nonroot-nonroot whoami
docker exec nonroot-nonroot id
```

### Étape 3 — Utiliser l'utilisateur intégré .NET

Partir du fichier `Dockerfile.dotnet` et utiliser l'utilisateur intégré `app` fourni par l'image `.NET 8` au lieu de créer un utilisateur manuellement.

Construire et tester :

```bash
# Construire l'image
docker build -t hello-nonroot:dotnet -f Dockerfile.dotnet .

# Lancer le conteneur
docker run -d -p 8080:8080 --name nonroot-dotnet hello-nonroot:dotnet

# Vérifier l'utilisateur
curl -s http://localhost:8080 | jq
docker exec nonroot-dotnet whoami
docker exec nonroot-dotnet id
```

### Validation

* [ ] `docker build` se termine sans erreur pour les trois Dockerfiles
* [ ] Avec `Dockerfile.root` : `whoami` retourne `root` et le JSON affiche `"user": "root"`
* [ ] Avec `Dockerfile.nonroot` : `whoami` retourne `appuser` et le JSON affiche `"user": "appuser"`
* [ ] Avec `Dockerfile.dotnet` : `whoami` retourne `app` et le JSON affiche `"user": "app"`
* [ ] `curl -s http://localhost:8080/health` retourne `{ "status": "up" }` pour les trois images
* [ ] L'application fonctionne correctement en non-root (pas d'erreur de permission)

### Commandes de build & run

```bash
# Construire les trois versions
docker build -t hello-nonroot:root -f Dockerfile.root .
docker build -t hello-nonroot:nonroot -f Dockerfile.nonroot .
docker build -t hello-nonroot:dotnet -f Dockerfile.dotnet .

# Lancer les conteneurs
docker run -d --name nonroot-root -p 8080:8080 hello-nonroot:root
docker run -d --name nonroot-nonroot -p 8080:8080 -d hello-nonroot:nonroot
docker run -d --name nonroot-dotnet -p 8080:8080 -d --name nonroot-test hello-nonroot:dotnet
```

Commandes utiles :

```bash
# Tester l'API
curl -s http://localhost:8080 | jq
curl -s http://localhost:8080/health | jq

# Vérifier l'utilisateur dans le conteneur
docker exec <conteneur> whoami
docker exec <conteneur> id

# Voir les permissions sur les fichiers
docker exec <conteneur> ls -la /app
```

### Bonus

* Tenter de lancer une commande `apt-get update` dans le conteneur non-root et observer l'erreur de permission

### Liens utiles

* [Documentation USER](https://docs.docker.com/reference/dockerfile/#user)
* [Documentation COPY --chown](https://docs.docker.com/reference/dockerfile/#copy---chown)
* [Bonnes pratiques de sécurité Docker](https://docs.docker.com/build/building/best-practices/#user)
* [Images .NET et utilisateur non-root](https://devblogs.microsoft.com/dotnet/securing-containers-with-rootless/)
* [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)

---

[⬅️ 05-troubleshooting](../../tree/05-troubleshooting) ·
[📋 Sommaire](../../tree/main) ·
[07-securite-secrets ➡️](../../tree/07-securite-secrets)

💡 [Voir la solution](../../tree/06-securite-non-root--solution)
