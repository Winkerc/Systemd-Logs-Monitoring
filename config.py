import os
from app.services import load_config

# Récupérer le chemin du fichier de configuration depuis la variable d'environnement
config_path = os.environ.get('PATH_CONFIG')

if not config_path:
    raise EnvironmentError(
        "ERREUR : La variable d'environnement 'PATH_CONFIG' n'est pas définie.\n"
        "Veuillez définir le chemin du fichier de configuration sécurisé :\n"
        "  export PATH_CONFIG='/etc/monitoring/config.yaml'\n"
        "Ou modifiez run_dev.py pour définir cette variable."
    )

if not os.path.exists(config_path):
    raise FileNotFoundError(
        f"ERREUR : Le fichier de configuration '{config_path}' n'existe pas.\n"
        "Veuillez exécuter setup_database.sh pour créer ce fichier."
    )

# Charger la configuration depuis le fichier sécurisé
cfg = load_config(config_path)
password = cfg['mariadb_logs_user_password']

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-key-change-in-production-123456'
    REMEMBER_COOKIE_DURATION = 3600  # Durée en secondes (1 heure)

    SQLALCHEMY_DATABASE_URI = f'mysql+pymysql://logs_user:{password}@localhost/logs_db'
    SQLALCHEMY_ENGINE_OPTIONS = {
        'pool_pre_ping': True,
        'pool_recycle': 3600,
        'pool_size': 10,
    }