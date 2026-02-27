#!/bin/sh
set -e

# Injection de la variable d'environnement BACKEND_URL dans index.html
sed -i "s|<head>|<head><script>window.__ENV__={BACKEND_URL:\"${BACKEND_URL:-}\"}</script>|" /app/build/index.html

# Démarrage de serve pour servir l'application sur le port 3000
npx serve -s /app/build -l 3000
