#!/bin/bash
# run_app.sh - Production server avec Gunicorn

# Charger les variables d'environnement depuis .env
if [ -f .env ]; then
    echo "Chargement de la configuration depuis .env..."
    export $(cat .env | grep -v '^#' | xargs)  # Exporte les variables d'environnement définies dans .env, xargs convertit les lignes en arguments sur une seule ligne, séparés par des espaces.
else
    echo "AVERTISSEMENT : Fichier .env introuvable"
    echo "Veuillez exécuter setup_database.sh pour le créer automatiquement"
fi

# Vérifier que PATH_CONFIG est défini
if [ -z "$PATH_CONFIG" ]; then
    echo "ERREUR : La variable PATH_CONFIG n'est pas définie."
    echo "Solution : Exécutez setup_database.sh qui créera le fichier .env automatiquement"
    exit 1
fi

# Vérifier que le fichier existe
if [ ! -f "$PATH_CONFIG" ]; then
    echo "ERREUR : Le fichier de configuration '$PATH_CONFIG' n'existe pas."
    echo "Veuillez exécuter setup_database.sh pour créer ce fichier."
    exit 1
fi

echo "Utilisation du fichier de configuration : $PATH_CONFIG"

# Utilise la venv créé par setup_database.sh
VENV_PYTHON="/opt/monitoring_venv/bin/python"
VENV_GUNICORN="/opt/monitoring_venv/bin/gunicorn"

echo "Démarrage du serveur Gunicorn..."
exec "$VENV_GUNICORN" \
    -w 2 \
    -b 0.0.0.0:5000 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    'app:create_app()'

    run_dev:app