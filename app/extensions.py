from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager

"""
Fichier qui sert à eviter les boucles d'appels circulaires.
"""

db = SQLAlchemy()
login_manager = LoginManager()