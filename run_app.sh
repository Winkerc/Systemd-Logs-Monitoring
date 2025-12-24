#!/bin/bash
# start_monitoring.sh

# Utilise la venv créée par setup_database.sh
exec /opt/monitoring_venv/bin/python run_dev.py "$@"