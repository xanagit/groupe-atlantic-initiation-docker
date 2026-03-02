# Troubleshooting Docker : solution

[⬅️ 04-dockerignore](../../tree/04-dockerignore) ·
[📋 Sommaire](../../tree/main) ·
[06-securite-non-root ➡️](../../tree/06-securite-non-root)

[📝 Retour à l'énoncé](../../tree/05-troubleshooting)

---

## Rappel de l'objectif

Utiliser les commandes de troubleshooting `Docker` (`docker logs`, `docker exec`, `docker inspect`, `docker stats`, `docker events`) pour diagnostiquer et résoudre des problèmes sur des conteneurs.

## Solution

### Préparation

Lancer le conteneur `nginx` en arrière-plan :

```bash
docker run -d --name web-test -p 8080:80 nginx:alpine
```

Vérifier que le conteneur tourne :

```bash
docker ps
# CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                                     NAMES
# 46a7939bc611   nginx:alpine   "/docker-entrypoint.…"   5 seconds ago   Up 4 seconds   0.0.0.0:8080->80/tcp, [::]:8080->80/tcp   web-test
```

### Étape 1 — Analyser les logs

#### 1. Afficher les logs du conteneur

```bash
docker logs web-test
# /docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
# /docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
# /docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
# 10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
# ...
# 2026/03/02 11:10:23 [notice] 1#1: using the "epoll" event method
# 2026/03/02 11:10:23 [notice] 1#1: nginx/1.29.5
# 2026/03/02 11:10:23 [notice] 1#1: built by gcc 15.2.0 (Alpine 15.2.0)
# ...
```

#### 2. Générer des requêtes HTTP

```bash
curl -s http://localhost:8080
curl -s http://localhost:8080
curl -s http://localhost:8080
```

#### 3. Observer les logs en temps réel

```bash
docker logs -f web-test
# ...
# 172.17.0.1 - - [xx/xxx/2025:xx:xx:xx +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.x.x"
# 172.17.0.1 - - [xx/xxx/2025:xx:xx:xx +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.x.x"
# 172.17.0.1 - - [xx/xxx/2025:xx:xx:xx +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.x.x"
```

> Chaque requête `curl` génère une ligne de log dans le conteneur. Le `-f` (follow) permet de visualiser les requêtes au fur et à mesure. La commande `Ctrl+C`permet de quitter le mode `follow`.

#### 4. Afficher les 5 dernières lignes en mode follow

```bash
docker logs -f --tail 5 web-test
# 172.17.0.1 - - [xx/xxx/2025:xx:xx:xx +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.x.x"
# 172.17.0.1 - - [xx/xxx/2025:xx:xx:xx +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.x.x"
# 172.17.0.1 - - [xx/xxx/2025:xx:xx:xx +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.x.x"
# ...
# Les nouvelles requêtes s'affichent ici au fur et à mesure
```

> L'option `--tail 5` évite d'afficher tout l'historique des logs. C'est une combinaison utile en production pour suivre les derniers événements sans être noyé par l'historique.

### Étape 2 — Explorer l'intérieur d'un conteneur

#### 1. Ouvrir un shell interactif

```bash
docker exec -it web-test /bin/sh
```

> L'image `nginx:alpine` (basée sur Alpine Linux) utilise `/bin/sh` (et non `/bin/bash`).

#### 2. Lister le contenu du répertoire HTML

```bash
# Dans le shell du conteneur
ls -la /usr/share/nginx/html/
# total 16
# drwxr-xr-x    2 root     root          4096 Feb  4 23:53 .
# drwxr-xr-x    3 root     root          4096 Feb  4 23:53 ..
# -rw-r--r--    1 root     root           497 Feb  4 20:18 50x.html
# -rw-r--r--    1 root     root           615 Feb  4 20:18 index.html
```

> Ce répertoire contient les fichiers servis par `nginx` par défaut : la page d'accueil `index.html` et la page d'erreur `50x.html`.

#### 3. Afficher le contenu du fichier `index.html`

```bash
# Dans le shell du conteneur
cat /usr/share/nginx/html/index.html
# <!DOCTYPE html>
# <html>
# <head>
# <title>Welcome to nginx!</title>
# ...
# </html>
```

#### 4. Afficher les variables d'environnement

```bash
# Dans le shell du conteneur
env
# PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# HOSTNAME=abc123def456
# TERM=xterm
# NGINX_VERSION=1.27.x
# NJS_VERSION=0.8.x
# NJS_RELEASE=1
# PKG_RELEASE=1
# DYNPKG_RELEASE=1
# HOME=/root
```

> On retrouve les variables standard (`PATH`, `HOSTNAME`) ainsi que les variables spécifiques à l'image `nginx` comme `NGINX_VERSION`. Le `HOSTNAME` contient l'ID du conteneur.

#### 5. Sortir du shell

```bash
exit
# Ou Ctrl + D
```

### Étape 3 — Inspecter la configuration

#### 1. Récupérer l'adresse IP du conteneur

```bash
# Commande pour rechercher le chemin JSON de l'adresse IP
docker inspect web-test | jq -c 'paths' | grep I
# Récupération de l'adresse IP
docker inspect --format '{{.NetworkSettings.Networks.bridge.IPAddress}}' web-test
# 172.17.0.2
```

#### 2. Récupérer le statut du conteneur

```bash
# Commande pour rechercher le chemin JSON du status
docker inspect web-test | jq -c 'paths' | grep Status
# Récupération du status
docker inspect --format '{{.State.Status}}' web-test
# running
```

#### 3. Lister les variables d'environnement via `docker inspect`

```bash
docker inspect --format '{{.Config.Env}}' web-test
# [PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin NGINX_VERSION=1.29.5 PKG_RELEASE=1 DYNPKG_RELEASE=1 NJS_VERSION=0.9.5 NJS_RELEASE=1 ACME_VERSION=0.3.1]
```

Utiliser `jq` pour un affichage plus lisible :

```bash
docker inspect web-test | jq '.[].Config.Env'
# [
#   "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
#   "NGINX_VERSION=1.29.5",
#   "PKG_RELEASE=1",
#   "DYNPKG_RELEASE=1",
#   "NJS_VERSION=0.9.5",
#   "NJS_RELEASE=1",
#   "ACME_VERSION=0.3.1"
# ]
```

> `docker inspect --format` utilise la syntaxe Go template. `jq` est souvent plus pratique pour naviguer dans le JSON.

#### 4. Afficher les ports exposés et leurs mappings

```bash
# Commande pour rechercher le chemin JSON du status
docker inspect web-test | jq -c 'paths' | grep -i port
# Récupération du port
docker inspect --format '{{.NetworkSettings.Ports}}' web-test
# map[80/tcp:[{0.0.0.0 8080} {:: 8080}]]
```

Avec `jq`  pour plus de lisibilité :

```bash
docker inspect web-test | jq '.[].NetworkSettings.Ports'
 # {
 #   "80/tcp": [
 #     {
 #       "HostIp": "0.0.0.0",
 #       "HostPort": "8080"
 #     },
 #     {
 #       "HostIp": "::",
 #       "HostPort": "8080"
 #     }
 #   ]
 # }
```

> Le port `80` du conteneur est mappé sur le port `8080` de l'hôte, conformément au `-p 8080:80` passé au `docker run`.

### Étape 4 — Surveiller les ressources

#### 1. Observer la consommation au repos

```bash
docker stats --no-stream web-test
# CONTAINER ID   NAME       CPU %     MEM USAGE / LIMIT     MEM %     NET I/O          BLOCK I/O         PIDS
# 46a7939bc611   web-test   0.00%     4.602MiB / 5.772GiB   0.08%     2.07kB / 1.4kB   8.19kB / 24.6kB   5
```

> Au repos, `nginx` consomme très peu de ressources : quasi 0% de CPU et quelques Mo de mémoire.

#### 2. Simuler de la charge

Dans un second terminal :

```bash
for i in $(seq 1 3000); do curl -s http://localhost:8080 > /dev/null; done
```

#### 3. Observer l'évolution avec `docker stats`

Dans le premier terminal :

```bash
docker stats web-test
# CONTAINER ID   NAME       CPU %     MEM USAGE / LIMIT    MEM %     NET I/O           BLOCK I/O         PIDS
# 46a7939bc611   web-test   1.62%     4.73MiB / 5.772GiB   0.08%     3.46MB / 7.53MB   8.19kB / 24.6kB   5
```

> Pendant la charge, on observe une augmentation du `CPU %` et du `NET I/O`. La mémoire reste stable car `nginx` gère de manière efficace les connexions.

### Étape 5 — Observer les événements

#### 1. Lancer l'écoute des événements

Dans un premier terminal :

```bash
docker events --filter container=web-test
```

#### 2. Manipuler le conteneur

Dans un second terminal :

```bash
docker stop web-test
docker start web-test
docker restart web-test
```

#### 3. Observer les événements générés

Le premier terminal affiche :

```bash
docker stop web-test
# 2026-03-02T14:13:07.074253260+01:00 container kill 46a7939bc (...)
# 2026-03-02T14:13:07.163512978+01:00 container stop 46a7939bc (...)
# 2026-03-02T14:13:07.164877973+01:00 container die 46a7939bc (...)

docker start web-test
# 2026-03-02T14:14:37.447997267+01:00 container start 46a7939bc (...)

docker restart web-test
# 2026-03-02T14:15:18.856547537+01:00 container kill 46a7939bc (... signal=3)
# 2026-03-02T14:15:18.949550526+01:00 container stop 46a7939bc (...)
# 2026-03-02T14:15:18.950907646+01:00 container die 46a7939bc (... exitCode=0)
# 2026-03-02T14:15:19.008289643+01:00 container start 46a7939bc (...)
# 2026-03-02T14:15:19.008302018+01:00 container restart 46a7939bc (...)
```

### Étape 6 — Diagnostiquer un conteneur qui crash

#### Lancer le conteneur cassé

```bash
docker run -d --name crash-test alpine sh -c "echo 'Démarrage...' && sleep 2 && exit 1"
```

#### 1. Vérifier l'état du conteneur

```bash
docker ps -a
# CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS                      PORTS   NAMES
# def789ghi012   alpine         "sh -c 'echo Démarr…"   10 seconds ago   Exited (1) 7 seconds ago            crash-test
# abc123def456   nginx:alpine   "/docker-entrypoint.…"   5 minutes ago    Up 2 minutes                ...     web-test
```

> Le statut `Exited (1)` indique que le conteneur s'est arrêté en erreur avec le code de sortie `1` (code `0` : arrêt normal).

#### 2. Lire les logs

```bash
docker logs crash-test
# Démarrage...
```

> Le conteneur a affiché "Démarrage...", attendu 2 secondes (`sleep 2`), puis s'est arrêté avec `exit 1`. Les logs montrent la dernière sortie avant le crash.

#### 3. Récupérer le code de sortie

```bash
# Trouver le chemin JSON d'accès de l'exit code
docker inspect crash-test | jq -c 'paths' | grep -i exit
# Récupération de l'exit code
docker inspect --format '{{.State.ExitCode}}' crash-test
# 1
```

Si l'on veut plus de détails sur l'état du conteneur, il est possible d'afficher tout le contenu du state :

```bash
docker inspect crash-test | jq '.[].State'
# {
#   "Status": "exited",
#   "Running": false,
#   "Paused": false,
#   "Restarting": false,
#   "OOMKilled": false,
#   "Dead": false,
#   "Pid": 0,
#   "ExitCode": 1,
#   "Error": "",
#   "StartedAt": "2026-03-02T13:25:37.996510807Z",
#   "FinishedAt": "2026-03-02T13:25:40.05484897Z"
# }
```

> Le champ `OOMKilled: false` indique que le conteneur n'a pas été tué par manque de mémoire. Le champ `ExitCode: 1` confirme une erreur applicative.

### Nettoyage

```bash
docker rm web-test crash-test
```

### Bonus : `docker inspect` pour comparer deux conteneurs

Lancer deux conteneurs avec des variables d'environnement différentes :

```bash
docker run -d --name app-dev -e APP_ENV=development nginx:alpine
docker run -d --name app-prod -e APP_ENV=production nginx:alpine
```

Comparer les variables d'environnement :

```bash
docker inspect app-dev | jq '.[].Config.Env' | grep APP_ENV
#  "APP_ENV=development",
docker inspect app-prod | jq '.[].Config.Env' | grep APP_ENV
#  "APP_ENV=production",
```

> Les deux conteneurs utilisent la même image mais ont des configurations différentes au runtime.

### Bonus : `docker cp` copier des fichiers vers le conteneur

#### Copier un fichier de l'hôte vers le conteneur

```bash
# Créer une page HTML personnalisée
echo "<h1>Ma super page d'accueil NGINX \!</h1>"  > ./custom.html

# Remplacer le index.html dans le conteneur
docker cp ./custom.html web-cp:/usr/share/nginx/html/index.html

# Vérifier le résultat
curl -s http://localhost:8080
# <h1>Page modifiée via docker cp</h1>
```

> `docker cp` peut servir pour extraire des fichiers de configuration ou pour injecter rapidement un fichier de test dans un conteneur.
> **Attention** : les modifications faites via `docker cp` ne persistent pas si le conteneur est recréé (elles ne modifient pas l'image).

### Bonus : `docker cp` copier des fichiers depuis le conteneur

```bash
docker run -d --name web-cp -p 8080:80 nginx:alpine

# Copier le fichier index.html depuis le conteneur
docker cp web-cp:/usr/share/nginx/html/index.html ./index.html

cat ./index.html
# <!DOCTYPE html>
# <html>
# <head>
# <title>Welcome to nginx!</title>
# ...
```

## Récapitulatif des points abordés

| Commande                                       | Usage principal                               | En complément                                            |
| ---------------------------------------------  | --------------------------------------------- | -------------------------------------------------------- |
| `docker logs -f --tail <N>`                    | Suivre les logs en temps réel                 | Combiner `-f` et `--tail` pour limiter l'affichage       |
| `docker exec -it <nom ou ID> /bin/sh`          | Explorer l'intérieur d'un conteneur           | Utiliser `/bin/sh` sur les images Alpine                 |
| `docker inspect --format`                      | Extraire une info précise (IP, ENV, état)     | Combiner avec `jq` pour un JSON lisible                  |
| `docker stats`                                 | Surveiller CPU, mémoire, réseau en temps réel | `--no-stream` pour un instantané                         |
| `docker events`                                | Observer les événements du daemon Docker      | `--filter container=X` pour filtrer sur un conteneur     |
| `docker inspect <nom ou ID> \| jq '.[].State'` | Comprendre pourquoi un conteneur a crashé     | Vérifier `OOMKilled` et `State.Status`                   |
| `docker cp`                                    | Copier des fichiers depuis/vers un conteneur  | Les modifications ne persistent pas au-delà du conteneur |

---

[⬅️ 04-dockerignore](../../tree/04-dockerignore) ·
[📋 Sommaire](../../tree/main) ·
[06-securite-non-root ➡️](../../tree/06-securite-non-root)

[📝 Retour à l'énoncé](../../tree/05-troubleshooting)
