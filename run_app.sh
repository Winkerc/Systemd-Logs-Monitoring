#!/bin/bash
# run_app.sh - Production server avec Gunicorn

# Utilise la venv créée par setup_database.sh
VENV_PYTHON="/opt/monitoring_venv/bin/python"
VENV_GUNICORN="/opt/monitoring_venv/bin/gunicorn"

echo "Démarrage du serveur Gunicorn..."
exec "$VENV_GUNICORN" \
    -w 2 \
    -b 0.0.0.0:5000 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    run_dev:app