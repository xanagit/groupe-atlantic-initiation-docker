# Build Multi-Stage : solution

[⬅️ 01-dockerisation-simple](../../tree/01-dockerisation-simple) ·
[📋 Sommaire](../../tree/main) ·
[03-docker-compose ➡️](../../tree/03-docker-compose)

📝 [Retour à l'énoncé](../../tree/02-multi-stage)

---

## Rappel de l'objectif

Adapter le Dockerfile et le rendre multi-stage afin de produire une image de production légère.

## Solution

### Dockerfile multi-stage (`Dockerfile`)

```dockerfile
# ---------- Stage 1 : Build ----------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copie du csproj et du code
COPY . .

# Restore des dépendances
RUN dotnet restore

# Publish
RUN dotnet publish -c Release -o /app/publish --no-restore

# ---------- Stage 2 : Runtime ----------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Copie seulement l'application publiée du stage build
COPY --from=build /app/publish .

EXPOSE 8080

ENTRYPOINT ["dotnet", "HelloMultiStage.dll"]
```

### Explication des points clés

#### `COPY --from=build`

L'instruction `COPY --from=build` permet de copier les fichiers depuis le stage nommé `build` vers le stage courant (`runtime`). Le stage `build` et tout son contenu (SDK, sources, `obj/`, etc.) ne sont pas gardés dans l'iamge finale.

#### Choix des images de base

- Stage `build` :
  - Image: `mcr.microsoft.com/dotnet/sdk:8.0`
  - Explication: Contient le CLI `dotnet`, le compilateur et les outils de restore 
- Stage `runtime` :
  - Image: `mcr.microsoft.com/dotnet/aspnet:8.0`
  - Contenu : Contient uniquement le runtime ASP.NET Core

### Comparaison des tailles d'image

Build des images :

```bash
docker build -t hello-multistage:single -f Dockerfile.single .
docker build -t hello-multistage:multi -f Dockerfile.multi .
```

Vérification de la taille des images :

```bash
docker image ls hello-multistage
# IMAGE                   CONTENT SIZE
# hello-multistage:multi        88.3MB
# hello-multistage:single        313MB
```

> L'image multi-stage est environ 3 fois plus petite que l'image single.

### Bonus : variante Alpine

Pour réduire encore la taille, il est possible de remplacer l'image de runtime par la variante Alpine :

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS final
```

Build de l'image :

```bash
docker build -t hello-multistage:alpine -f Dockerfile.alpine .
```

La taille de l'image fait environs **~47 MB**.

### Bonus : HEALTHCHECK

Ajouter `HEALTHCHECK` dans le stage `runtime`, avant `ENTRYPOINT` :

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
```

Build de l'image :

```bash
docker build -t hello-multistage:health -f Dockerfile.health .
```

Inspection du health status du conteneur :

```bash
# Run
docker run -d -p 8080:8080 --name hello-multistage-health hello-multistage:health
# Inspect
docker inspect --format='{{json .State.Health}}' hello-multistage-health | jq
```

---

[⬅️ 01-dockerisation-simple](../../tree/01-dockerisation-simple) ·
[📋 Sommaire](../../tree/main) ·
[03-docker-compose ➡️](../../tree/03-docker-compose)

📝 [Retour à l'énoncé](../../tree/02-multi-stage)
