# Troubleshooting Docker

[⬅️ 04-dockerignore](../../tree/04-dockerignore) ·
[📋 Sommaire](../../tree/main) ·
[06-securite-non-root ➡️](../../tree/06-securite-non-root)

💡 [Voir la solution](../../tree/05-troubleshooting--solution)

---

## Contexte

Un conteneur `Docker` est une boîte fermée : on ne voit pas ce qu'il se passe à l'intérieur. Quand une application ne démarre pas, plante silencieusement ou se comporte de manière inattendue, il faut des outils pour investiguer.

Docker fournit un ensemble de commandes qui permettent de :

* **Lire les logs** d'un conteneur pour comprendre ce qu'il affiche sur `stdout` et `stderr`
* **Entrer dans un conteneur** pour inspecter son système de fichiers et exécuter des commandes
* **Inspecter la configuration** d'un conteneur (variables d'environnement, volumes, état, ...)
* **Surveiller les ressources** consommées par un conteneur (CPU, mémoire, réseau)
* **Observer les événements** du daemon Docker en temps réel

## Les commandes essentielles

### `docker logs` — Lire les logs d'un conteneur

Chaque conteneur écrit ses logs sur `stdout` et `stderr`. La commande `docker logs` permet de visualiser les logs comme `tail -f` le ferait.

```bash
# Afficher tous les logs d'un conteneur
docker logs <ID conteneur ou name>

# Suivre les logs en temps réel (comme tail -f)
docker logs -f <ID conteneur ou name>

# Afficher les logs avec les timestamps
# Redondant si le logger affiche déjà la date
docker logs -t <ID conteneur ou name>

# Affiche les 5 dernières lignes des logs 
docker logs --tail 5 <ID conteneur ou name>

# Combiner les options
docker logs -ft <ID conteneur ou name>
```

> **Bonne pratique** : dans un conteneur `Docker`, l'application ne doit jamais écrire ses logs dans un fichier. Elle doit écrire sur `stdout`/`stderr` pour que `Docker` (et les outils d'orchestration comme Kubernetes) puissent les collecter automatiquement.

### `docker exec` — Exécuter une commande dans un conteneur

`docker exec` permet d'exécuter une commande à l'intérieur d'un conteneur en cours d'exécution. C'est l'équivalent d'un `ssh` pour un conteneur.

```bash
# Ouvrir un shell interactif dans un conteneur
docker exec -it <ID conteneur ou name> /bin/sh

# Ouvrir un shell bash dans le conteneur (s'il est disponible)
docker exec -it <ID conteneur ou name> /bin/bash

# Exécuter une simple commande
docker exec <ID conteneur ou name> ls -la /app

# Afficher toutes les variables d'environnement
docker exec <ID conteneur ou name> env
# Afficher le contenu d'une variable d'environnement
docker exec <ID conteneur ou name> printenv APP_ENVIRONMENT

# Tester la connectivité réseau depuis le conteneur (port 80 pour nginx)
docker exec <ID conteneur ou name> curl http://localhost:80
```

> **Attention** : les images basées sur `alpine` ne contiennent pas `/bin/bash`, il faut utiliser `/bin/sh`. De manière générale, les images de production sont minimalistes et ne contiennent pas d'outils comme `curl`, `wget` ou `vim`. C'est normal et voulu pour des raisons de sécurité et de taille d'image.

### `docker inspect` — Inspecter la configuration d'un conteneur

Comme vu lors des parties précédentes, `docker inspect` retourne toute la configuration d'un conteneur ou d'une image au format JSON. C'est la commande la plus complète pour comprendre l'état d'un conteneur.

```bash
# Inspecter un conteneur
docker inspect <ID conteneur ou name>

# Filtrer avec --format pour extraire une information précise

# Voir les variables d'environnement
docker inspect --format '{{.Config.Env}}' <ID conteneur ou name>

# Voir l'état du conteneur (running, exited, etc.)
docker inspect --format '{{.State.Status}}' <ID conteneur ou name>

# Voir le code de sortie d'un conteneur arrêté
docker inspect --format '{{.State.ExitCode}}' <ID conteneur ou name>

# Voir les ports exposés et leurs mappings
docker inspect --format '{{.NetworkSettings.Ports}}' <ID conteneur ou name>

# Voir les volumes montés
docker inspect --format '{{.Mounts}}' <ID conteneur ou name>

# Inspecter une image (voir ses layers, ENV, CMD, etc.)
docker inspect <image>
```

> **Astuce** : le résultat de `docker inspect` est un JSON. Il est possible d'utiliser `jq` pour faciliter la récupération d'information : `docker inspect <conteneur> | jq '.[].Config.Env'`.

### `docker stats` — Surveiller les ressources en temps réel

`docker stats` affiche en temps réel la consommation CPU, mémoire, réseau et I/O disque de chaque conteneur. C'est l'équivalent de la commande `top` pour les conteneurs.

```bash
# Surveiller tous les conteneurs en cours d'exécution
docker stats

# Surveiller un conteneur spécifique
docker stats <ID conteneur ou name>
# Sans le rafraîchissement
docker stats --no-stream
```

Colonnes affichées par `docker stats` :

* `CPU %` : Pourcentage CPU utilisé par le conteneur
* `MEM USAGE / LIMIT` : Mémoire utilisée vs mémoire maximale autorisée
* `MEM %` : Pourcentage mémoire utilisé
* `NET I/O` : Données réseau entrantes / sortantes
* `BLOCK I/O` : Données lues / écrites sur le disque
* `PIDS` : Nombre de processus dans le conteneur

> La commande `docker stats` est généralement utilisée pour détecter une fuite mémoire ou un conteneur qui consomme trop de CPU.

### `docker events` — Observer les événements du daemon Docker

La commande `docker events` affiche en temps réel les événements émis par le daemon Docker : création, démarrage, arrêt, suppression de conteneurs, etc. C'est l'équivalent d'un journal d'audit.

```bash
# Écouter et suivre tous les événements
docker events

# Filtrer les événements sur une plage de temps
docker events --since 10m --until 5m
```

Exemples d'événements observables :

* `create` : Un conteneur a été créé
* `start` : Un conteneur a démarré
* `die` : Un conteneur s'est arrêté (crash ou arrêt normal)
* `stop` : Un conteneur a été arrêté manuellement
* `kill` : Un conteneur a été tué (signal envoyé)
* `destroy` : Un conteneur a été supprimé
* `oom` : Un conteneur a été tué par le système (Out Of Memory)

> La commande `docker events` peut être utile pour comprendre pourquoi un conteneur crash au démarrage et redémarre en boucle.
> La liste complète des événements Docker est accessible ici : [docker system events](https://docs.docker.com/reference/cli/docker/system/events/).

## Récapitulatif des commandes

* Voir ce que l'application affiche : `docker logs -f <conteneur>`
* Entrer dans le conteneur : `docker exec -it <conteneur> /bin/sh`
* Voir la config complète (IP, ENV, état...) : `docker inspect <conteneur>`
* Surveiller CPU / mémoire en temps réel : `docker stats`
* Voir les événements Docker (start, die...) : `docker events`

## Mise en pratique

### But

Utiliser les commandes de troubleshooting `Docker` pour diagnostiquer et résoudre des problèmes sur des conteneurs.

### Préparation

Lancer un conteneur `nginx` en arrière-plan :

```bash
docker run -d --name web-test -p 8080:80 nginx:alpine
```

Vérifier que le conteneur tourne :

```bash
docker ps
```

### Étape 1 — Analyser les logs

1. Afficher les logs du conteneur `web-test`
2. Lancer plusieurs fois la commande `curl -s http://localhost:8080`
3. Observer les logs en temps réel en mode `follow` (option `f`) et vérifier les logs des nouvelles requêtes
4. Afficher uniquement les 5 dernières lignes de logs en mode `follow`

### Étape 2 — Explorer l'intérieur d'un conteneur

1. Ouvrir un shell interactif dans le conteneur `web-test`
2. Lister le contenu du répertoire `/usr/share/nginx/html/`
3. Afficher le contenu du fichier `index.html`
4. Afficher toutes les variables d'environnement du conteneur
5. Sortir du shell avec `exit`

### Étape 3 — Inspecter la configuration

1. Récupérer l'adresse IP du conteneur `web-test` en utilisant `docker inspect` avec l'option `--format`
2. Récupérer le statut du conteneur (`running`, `exited`, etc.)
3. Lister les variables d'environnement définies dans l'image via `docker inspect`
4. Afficher les ports exposés et leurs mappings

### Étape 4 — Surveiller les ressources

1. Lancer `docker stats` et observer la consommation du conteneur `web-test` au repos
2. Dans un autre terminal, simuler de la charge :

    ```bash
    # Envoyer 1000 requêtes sur le conteneur
    for i in $(seq 1 3000); do curl -s http://localhost:8080 > /dev/null; done
    ```

3. Observer l'évolution du CPU et du réseau avec `docker stats`

### Étape 5 — Observer les événements

1. Ouvrir un terminal dédié et lancer `docker events --filter container=web-test`
2. Dans un autre terminal, exécuter successivement :

   ```bash
    docker stop web-test
    docker start web-test
    docker restart web-test
   ```

3. Observer les événements générés dans le premier terminal

### Étape 6 — Diagnostiquer un conteneur qui crash

Simuler le crash au démarrage d'un conteneur :

```bash
docker run -d --name crash-test alpine sh -c "echo 'Démarrage...' && sleep 2 && exit 1"
```

1. Vérifier l'état du conteneur avec `docker ps -a` (noter le statut `Exited`)
2. Lire les logs pour comprendre ce qu'il s'est passé
3. Récupérer le code de sortie du conteneur avec `docker inspect`

### Nettoyage

```bash
docker rm web-test crash-test
```

### Validation

* [ ] Les logs du conteneur `web-test` affichent les requêtes HTTP entrantes
* [ ] Connexion en mode interactif dans le conteneur et affichage du fichier `index.html`
* [ ] L'adresse IP du conteneur a été récupérée via `docker inspect`
* [ ] Vérification de l'augmentation du CPU et réseau pendant la simulation de montée en charge avec `docker stats`
* [ ] Vérification des événements `stop`, `start`, `die` avec la commande `docker events`
* [ ] Le code de sortie `1` du conteneur `crash-test` a été identifié via `docker inspect`

### Bonus

* Utiliser `docker inspect` pour comparer la configuration de deux conteneurs lancés à partir de la même image mais avec des variables d'environnement différentes
* Utiliser `docker cp` pour copier un fichier vers le conteneur nginx : remplacer le fichier index.html
* Utiliser `docker cp` pour copier un fichier depuis le conteneur

### Liens utiles

* [Documentation docker logs](https://docs.docker.com/reference/cli/docker/container/logs/)
* [Documentation docker exec](https://docs.docker.com/reference/cli/docker/container/exec/)
* [Documentation docker inspect](https://docs.docker.com/reference/cli/docker/inspect/)
* [Documentation docker stats](https://docs.docker.com/reference/cli/docker/container/stats/)
* [Documentation docker events](https://docs.docker.com/reference/cli/docker/system/events/)
* [Documentation des commandes de référence](https://docs.docker.com/reference/dockerfile/)

---

[⬅️ 04-dockerignore](../../tree/04-dockerignore) ·
[📋 Sommaire](../../tree/main) ·
[06-securite-non-root ➡️](../../tree/06-securite-non-root)

💡 [Voir la solution](../../tree/05-troubleshooting--solution)
