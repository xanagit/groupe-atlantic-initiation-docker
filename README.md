# Rappels des concepts Docker vu lors du RETEX

[📋 Sommaire](../../tree/main) ·
[01-dockerisation-simple ➡️](../../tree/01-dockerisation-simple)

---

## Pourquoi Docker ?

### L'analogie du conteneur maritime

Avant 1961, le transport de marchandises reposait sur des formats hétérogènes (caisses, sacs, palettes, fûts, ballots), rendant le chargement lent et manuel. L'invention du conteneur standardisé a permis l'industrialisation de la logistique : grues, bateaux et camions manipulent tous le même format.

Docker implémente le même principe au monde logiciel :

- **Avant Docker** : chaque application a son propre runtime et sa propre configuration d'infrastructure (`.NET + IIS`, `Node.js + PM2`, `PHP + Apache`). L'infrastructure est configurée manuellement, de manière non standardisée.
- **Après Docker** : chaque application est empaquetée dans une image Docker, quel que soit le langage ou le framework. Cela permet d'utiliser les mêmes pipelines CI/CD, le même runtime et la même infrastructure pour toutes les applications.

> **Principe clé** : standardiser le contenant pour gérer les applications de manière identique.

## Machine Virtuelle vs Conteneur

### Machine Virtuelle (VM)

Une VM embarque un OS complet au-dessus d'un hyperviseur (VMware, Hyper-V). Chaque VM contient :

- L'application
- Ses librairies et dépendances
- Un système d'exploitation entier

La pile complète est donc : Infrastructure physique → Hyperviseur → OS invité → Libs/Deps → Application.

### Conteneur

Un conteneur partage le noyau du système d'exploitation hôte. Il ne contient que :

- L'application
- Ses librairies et dépendances

La pile est : Infrastructure physique → OS hôte → Docker Engine → Libs/Deps → Application.

### Différence fondamentale

Le conteneur est plus léger car il n'a pas besoin d'embarquer un OS complet. Il s'appuie sur le noyau de la machine hôte, ce qui réduit considérablement la consommation de ressources et le temps de démarrage.

### Avantages des conteneurs

- **Démarrage rapide** : Un conteneur démarre en quelques secondes, contre plusieurs minutes pour une VM
- **Reproductible** : Une même image produit exactement le même comportement quel que soit l'environnement d'exécution
- **Léger** : Le conteneur partage le noyau de l'hôte et n'embarque pas un OS complet, ce qui le rend très économe en ressources
- **Portable** : La même image fonctionne sur le poste de développement, en intégration, en préprod et en production.

## Du Dockerfile au conteneur

Le cycle de vie d'une application conteneurisée suit trois étapes.

### 1. Le Dockerfile

Il contient les instructions permettant de construire l'image :

```dockerfile
FROM node:24-alpine            # Image de base
WORKDIR /app                   # Répertoire de travail
COPY . /app                    # Copie du code source
RUN npm install                # Installation des dépendances
ENTRYPOINT ["node", "app.js"]  # Commande de démarrage
```

### 2. L'image Docker

Le résultat du `docker build`. C'est un livrable immutable qui contient tout le nécessaire pour exécuter l'application : code, dépendances, runtime et configuration.

L'image est ensuite poussée (`push`) vers un Container Registry (par exemple Azure Container Registry — ACR) pour être stockée et partagée.

### 3. Le conteneur

C'est une instance en cours d'exécution de l'image récupérée depuis la registry (`pull`), puis on la lance. Plusieurs conteneurs peuvent être créés à partir de la même image.

### Flux complet

> **Dockerfile**  →  (build)  →  **Image Docker**  →  (push)  →  **Container Registry  / ACR** ← (pull) ← **Conteneur (instance en exécution)**

---

[📋 Sommaire](../../tree/main) ·
[01-dockerisation-simple ➡️](../../tree/01-dockerisation-simple)
