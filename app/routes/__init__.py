from flask import Blueprint

# importer tous les blueprints dans routes
# (il peut y en avoir d'autres)
from app.routes.routes import main

# Créer une liste des blueprints à enregistrer dans l'app.
blueprints = [main]
