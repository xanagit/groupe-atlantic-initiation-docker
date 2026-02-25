# Dockerisation simple : solution

[⬅️ 00-rappels](../../tree/00-rappels) ·
[📋 Sommaire](../../tree/main) ·
[02-multi-stage ➡️](../../tree/02-multi-stage)

📝 [Retour à l'énoncé](../../tree/01-dockerisation-simple)

---

## Rappel de l'objectif

Conteneuriser l'application Node.js (Express) qui écoute sur le port `3000` et répond `Hello Docker!` sur la route `/`.

## Solution de base

### Dockerfile

```dockerfile
# 1. Selectionne l'image de base du Docker Hub
FROM node:25

# 2. Défini le répertoire de travail dans le conteneur
WORKDIR /app

# 3. Copie de tout le répertoire coutant dans le dossier /app du conteneur
COPY . .

# 4. Installation des dépendences en utilisant npm ci (utilisation du package-lock)
RUN npm ci

# 5. Documente le port d'exposition
EXPOSE 3000

# 6. Défini la commande de démarrage
CMD ["node", "server.js"]
```

### `npm ci` vs `npm install`

| Aspect               | `npm install`       | `npm ci`                   |
|----------------------|---------------------|----------------------------|
| Fichier de référence | `package.json`      | `package-lock.json`        |
| Reproductibilité     | ⚠️ Peut varier      | ✅ Identique à chaque fois |
| Vitesse              | Plus lent           | Plus rapide                |
| Usage recommandé     | Développement local | CI/CD et Docker            |

> `npm ci` supprime `node_modules` s'il existe et installe exactement les versions du `package-lock.json`. C'est le choix idéal pour un Dockerfile.

---

## Build & Run

```bash
# Construction de l'image avec le tag "base"
docker build -t hello-docker:base -f Dockerfile.base .

# Lancement du conteneur en mappant le port 3000
docker run -p 3000:3000 hello-docker:base

# Test curl
curl http://localhost:3000
# → {"message": "Hello Docker!"}
```

### Options utiles de `docker run`

```bash
# Lancement en mode detached (en arrière-plan)
docker run -p 3000:3000 -d hello-docker:base

# Lancement en mode detached & en le nommant
docker run -p 3000:3000 -d --name hello-docker-base hello-docker:base
```

---

## Bonus 1 — Image légère avec Alpine

L'image `node:25` est basée sur Debian et pèse **~415 Mo**. L'image `node:25-alpine` est basée sur Alpine Linux et pèse **~60 Mo**.

```dockerfile
# Utilise node Alpine pour une taille d'image réduite
FROM node:25-alpine

WORKDIR /app

COPY . .

RUN npm ci

EXPOSE 3000

CMD ["node", "server.js"]
```

### Commande de build & run

```bash
# Build
docker build -t hello-docker:alpine -f Dockerfile.alpine .
# Run
docker run -p 3000:3000 -d hello-docker:alpine
# Test
curl http://localhost:3000
```

### Comparaison des tailles d'image

```bash
docker image ls
# IMAGE               CONTENT SIZE
# hello-docker:base          402MB
# hello-docker:alpine       64.7MB
```

## Bonus 2 — HEALTHCHECK

Le `HEALTHCHECK` permet à Docker de vérifier périodiquement si le conteneur fonctionne correctement.

```dockerfile
# Utilise node Alpine pour une taille d'image réduite
FROM node:25-alpine

WORKDIR /app

COPY . .

RUN npm ci

EXPOSE 3000

# Health check: Vérifie que l'application répond sur / (health check)
# --interval: temps entre les vérifications
# --timeout: timeout du helath check
# --start-period: délais avant les health check au démarrage
# --retries: nombre de tentatives avant de marquer le contereur "unhealthy"
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
   # Non verbeux, unique essai, requête HEAD (--spider), arrête le conteneur en cas d'échec 
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/ || exit 1

CMD ["node", "server.js"]
```

> Utilisation de `wget` et non `curl` car le binaire existe de base sur Alpine (évite l'installation d'un binaire).
> `HEALTHCHECK` dans Kubernetes :
> Dans un environnement Kubernetes, le `HEALTHCHECK` n'est pas utilisé. Kubernetes utilise directement les endpoints de health check de l'application.

### Vérifier le health check

```bash
# Build
docker build -t hello-docker:healthcheck -f Dockerfile.healthcheck .
# Run
docker run -p 3000:3000 --name hello-docker-healthcheck -d hello-docker:healthcheck

# Inspection du health state (jq)
docker inspect hello-docker-healthcheck | jq '.[].State.Health'

# Inspection du health state (--format)
docker inspect --format='{{json .State.Health}}' hello-docker-healthcheck | jq
```

Résultat de la commande :

```json
{
  "Status": "healthy",
  "FailingStreak": 0,
  "Log": [
    {
      "Start": "2026-02-25T11:37:51.756692353+01:00",
      "End": "2026-02-25T11:37:51.79867128+01:00",
      "ExitCode": 0,
      "Output": "Connecting to localhost:3000 ([::1]:3000)\nremote file exists\n"
    },
    {
      "Start": "2026-02-25T11:38:21.804455575+01:00",
      "End": "2026-02-25T11:38:21.850594241+01:00",
      "ExitCode": 0,
      "Output": "Connecting to localhost:3000 ([::1]:3000)\nremote file exists\n"
    }
  ]
}
```

> Les états possibles sont : `starting`, `healthy` ou `unhealthy`.

## Bonus 3 — Gestion des signaux (SIGINT / SIGTERM)

### Le problème

Lors de la commande `docker stop <container ID>`, Docker envoie un signal `SIGTERM` au processus du conteneur. Si le processus ne gère pas ce signal, Docker attend 10 secondes puis envoie un `SIGKILL` (arrêt brutal).
En cas de lancement en mode non detached (sans `-d`) et sans gestion du `SIGINT`, la commande `Ctrl + C` n'arrête pas le conteneur.

### Comportement avec les handlers `SIGTERM` et `SIGINT`

Si l'application intercepte `SIGINT` et `SIGTERM` :

```javascript
process.on('SIGTERM', () => {
  console.log('Shutting down...');
  server.close(() => process.exit(0));
});

process.on('SIGINT', () => {
  console.log('Shutting down...');
  server.close(() => process.exit(0));
});
```

Alors, `docker stop` arrête le conteneur immédiatement (arrêt gracieux).

### Comportement sans les handlers

Sans les handlers, `Node.js` ne réagit pas au `SIGTERM` :

`docker stop` attend 10 secondes (timeout Docker par défaut) puis tue le processus avec `SIGKILL`.

```bash
# Build
docker build -t hello-docker:nohandlers -f Dockerfile.nohandlers .
# Run des conteneurs (1 avec les handlers, 1 sans)
docker run -p 3000:3000 --name hello-docker-with-handlers -d hello-docker:healthcheck
docker run -p 3001:3000 --name hello-docker-no-handlers -d hello-docker:nohandlers

# Avec handlers : arrêt quasi instantané
time docker stop hello-docker-with-handlers
# hello-docker-with-handlers
# docker stop hello-docker-with-handlers  0,01s user 0,01s system 15% cpu 0,108 total

# Sans handlers : attend le timeout (~10 secondes)
time docker stop hello-docker-no-handlers
# hello-docker-no-handlers
# docker stop hello-docker-no-handlers  0,01s user 0,01s system 0% cpu 10,138 total
```

> En production (et surtout sur Kubernetes), l'arrêt gracieux est important car il permet de :
>
> - Terminer les requêtes HTTP en cours
> - Fermer proprement les connexions à la base de données
> - Libérer les ressources
> - Éviter la perte ou corruption de données
>
> La gestion du `SIGTERM` est un prérequis pour un bon fonctionnement sur Kubernetes qui l'utilise notamment pour le rolling update et le scale down.

---

## Récapitulatif des points abordés

| Bonne pratique                       | Pourquoi                               |
|--------------------------------------|----------------------------------------|
| Utiliser `npm ci`                    | Builds reproductibles                  |
| Préférer les images `Alpine`         | Réduction de la taille de l'image      |
| `HEALTHCHECK`                        | Monitoring intégré du conteneur        |
| Gestion des signaux                  | Arrêt gracieux, essentiel pour K8s     |
| `EXPOSE`                             | Documentation du port (bonne pratique) |

---

[⬅️ 00-rappels](../../tree/00-rappels) ·
[📋 Sommaire](../../tree/main) ·
[02-multi-stage ➡️](../../tree/02-multi-stage)

📝 [Retour à l'énoncé](../../tree/01-dockerisation-simple)
