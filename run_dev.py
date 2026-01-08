from app import create_app
import os

# Charger les variables d'environnement depuis le fichier .env
try:
    from dotenv import load_dotenv
    load_dotenv()  # Charge automatiquement .env dans le répertoire courant
except ImportError:
    print("AVERTISSEMENT : python-dotenv n'est pas installé.")
    print("Veuillez exécuter : pip install python-dotenv")
    print("Ou réexécuter setup_database.sh qui l'installera automatiquement.")

# Vérifier que PATH_CONFIG est défini
if not os.environ.get('PATH_CONFIG'):
    print("ERREUR : La variable PATH_CONFIG n'est pas définie.")
    print("Solution 1 : Exécutez setup_database.sh qui créera le fichier .env automatiquement")
    print("Solution 2 : Créez manuellement un fichier .env avec : PATH_CONFIG=/etc/monitoring/config.yaml")
    exit(1)

# Vérifier que le fichier existe
config_path = os.environ['PATH_CONFIG']
if not os.path.exists(config_path):
    print(f"ERREUR : Le fichier de configuration '{config_path}' n'existe pas.")
    print("Veuillez exécuter setup_database.sh pour créer ce fichier.")
    exit(1)

print(f"[INFO] Utilisation du fichier de configuration : {config_path}")

app = create_app()

def main():
    app.run(debug=True)

if __name__== '__main__':
    main()