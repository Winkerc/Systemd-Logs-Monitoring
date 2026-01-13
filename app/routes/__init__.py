from flask import Blueprint

# importer tous les blueprints dans routes
from app.routes.routes import main
from app.routes.auth import auth_bp
from app.routes.serveurs import serveurs_bp
from app.routes.journaux import journaux_bp
from app.routes.utilisateurs import utilisateurs_bp

# Créer une liste des blueprints à enregistrer dans l'app.
blueprints = [main, auth_bp, serveurs_bp, journaux_bp, utilisateurs_bp]
