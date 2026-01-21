#!/bin/bash

# Script de configuration de la base de données
# Usage: ./setup_database.sh <password>

set -e

log_info() { echo "[INFO] $1"; }
log_error() { echo "[ERROR] $1"; }

show_usage() {
    cat << EOF
Usage: $0 [config_path] <password>

Arguments:
    [config_path]      (Optionnel) Le chemin vers lequel sera créé le fichier config.
                       Par défaut: /etc/monitoring/config.yaml
                       Ce fichier contiendra les informations sensibles (mot de passe MariaDB,
                       chemin de la clé SSH, utilisateur SSH).

    <password>         Mot de passe pour l'utilisateur MySQL 'logs_user'
                       Ce mot de passe sera stocké dans le fichier de configuration sécurisé.

Note: Ce script doit être exécuté en tant que root.
      Un utilisateur admin (admin/admin) sera créé automatiquement dans la base de donnée.

Exemple:
    $0 admin                                    # Utilise /etc/monitoring/config.yaml
    $0 /opt/monitoring/config.yaml admin       # Utilise un chemin personnalisé
EOF
    exit 1
}

# Gestion des arguments
if [ $# -eq 1 ]; then  # $# compte le nombre d'arguments passés au script
    CONFIG_PATH="/etc/monitoring/config.yaml"
    DB_PASSWORD="$1"
elif [ $# -eq 2 ]; then
    CONFIG_PATH="$1"
    DB_PASSWORD="$2"
else
    log_error "Nombre d'arguments incorrect"
    echo ""
    show_usage
fi


if [[ $EUID -ne 0 ]]; then  # $EUID contient l'ID utilisateur effectif
   log_error "Ce script doit être exécuté en tant que root"
   exit 1
fi

log_info "Configuration de la base de données pour le monitoring..."

if ! command -v mysql &> /dev/null; then # command -v vérifie si une commande existe dans le système, sans l'exécuter.
    log_info "Installation de MariaDB..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        --no-install-recommends \
        mariadb-server mariadb-client  # Installer MariaDB sans les paquets recommandés pour minimiser l'installation
    systemctl enable mariadb
    systemctl start mariadb
else
    log_info "MariaDB déjà installé"
fi

if ! command -v python3 &> /dev/null; then
    log_info "Installation de Python3..."
    apt-get install -y -qq python3 python3-venv
else
    log_info "Python3 déjà installé"
fi

if ! dpkg -l | grep -q python3-venv; then  # dpkg -l liste les paquets installés, grep -q vérifie silencieusement la présence du paquet
    log_info "Installation de python3-venv..."
    apt-get install -y -qq python3-venv
fi

VENV_DIR="/opt/monitoring_venv"
log_info "Création de l'environnement virtuel Python dans $VENV_DIR..."

if [ -d "$VENV_DIR" ]; then
    log_info "Suppression de l'ancien venv..."
    rm -rf "$VENV_DIR"
fi

python3 -m venv "$VENV_DIR"

log_info "Installation des dépendances Python dans le venv..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip

log_info "Installation de mysql-connector-python..."
"$VENV_DIR/bin/pip" install --quiet mysql-connector-python

log_info "Installation de pymysql..."
"$VENV_DIR/bin/pip" install --quiet "pymysql"

log_info "Installation de SQLAlchemy..."
"$VENV_DIR/bin/pip" install --quiet "sqlalchemy~=2.0.43"

log_info "Installation de Flask et extensions..."
"$VENV_DIR/bin/pip" install --quiet "flask~=3.1.2"
"$VENV_DIR/bin/pip" install --quiet "flask-login~=0.6.3"
"$VENV_DIR/bin/pip" install --quiet "werkzeug~=3.1.3"
"$VENV_DIR/bin/pip" install --quiet "flask_sqlalchemy"

log_info "Installation de Gunicorn..."
"$VENV_DIR/bin/pip" install --quiet "gunicorn"

log_info "Installation de PyYAML..."
"$VENV_DIR/bin/pip" install --quiet "pyyaml~=6.0.3"

log_info "Installation de Paramiko et Fabric2..."
"$VENV_DIR/bin/pip" install --quiet "paramiko~=4.0.0"
"$VENV_DIR/bin/pip" install --quiet --index-url https://pypi.python.org/simple "fabric2~=3.2.2"  # Spécifier l'index pour éviter les problèmes de résolution de dépendances (cela m'a cosé certains soucis)

log_info "Installation de python-dotenv..."
"$VENV_DIR/bin/pip" install --quiet "python-dotenv"

log_info "Toutes les dépendances Python ont été installées"

log_info "Génération du hash du mot de passe admin..."

# Générer le hash du mot de passe 'admin' avec Python/Werkzeug
ADMIN_HASH=$("$VENV_DIR/bin/python" -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('admin'))")

log_info "Configuration de la base de données..."

SQL_FILE="/tmp/setup_db.sql"

cat > "$SQL_FILE" << EOF
CREATE DATABASE IF NOT EXISTS logs_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS 'logs_user'@'localhost';
CREATE USER 'logs_user'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON logs_db.* TO 'logs_user'@'localhost';
FLUSH PRIVILEGES;

USE logs_db;

CREATE TABLE IF NOT EXISTS roles (
    id INT PRIMARY KEY,
    description VARCHAR(50) NOT NULL,
    privileges INT NOT NULL
);

INSERT INTO roles (id, description, privileges) VALUES
(1, 'utilisateur', 1),
(2, 'gestionnaire', 3),
(3, 'admin', 7)
ON DUPLICATE KEY UPDATE description=VALUES(description), privileges=VALUES(privileges);

CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role_id INT NOT NULL,
    FOREIGN KEY (role_id) REFERENCES roles(id)
);

INSERT INTO users (username, password_hash, role_id) VALUES
('admin', '$ADMIN_HASH', 3)
ON DUPLICATE KEY UPDATE password_hash=VALUES(password_hash), role_id=VALUES(role_id);

CREATE TABLE IF NOT EXISTS servers (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    ip VARCHAR(45) NOT NULL,
    description TEXT
);
EOF

if mysql -u root < "$SQL_FILE" 2>&1; then  # 2>&1 redirige stderr vers stdout pour capturer les erreurs
    log_info "Base de données configurée avec succès"
else
    log_error "Erreur lors de la configuration de la base de données"
    rm -f "$SQL_FILE"
    exit 1
fi

rm -f "$SQL_FILE"

log_info "Vérification de la configuration..."

VERIFY_SCRIPT="/tmp/verify_db.py"

cat > "$VERIFY_SCRIPT" << PYEOF
import mysql.connector
import sys

try:
    conn = mysql.connector.connect(
        host='localhost',
        user='logs_user',
        password='$DB_PASSWORD',
        database='logs_db'
    )
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM roles")
    roles_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM users")
    users_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM servers")
    servers_count = cursor.fetchone()[0]

    cursor.close()
    conn.close()

    print(f"Roles: {roles_count}, Users: {users_count}, Servers: {servers_count}")

except mysql.connector.Error as err:
    print(f"Erreur: {err}", file=sys.stderr)
    sys.exit(1)
PYEOF

if "$VENV_DIR/bin/python" "$VERIFY_SCRIPT" > /dev/null 2>&1; then
    log_info "Vérification réussie"
else
    log_error "Échec de la vérification"
    rm -f "$VERIFY_SCRIPT"
    exit 1
fi

rm -f "$VERIFY_SCRIPT"

log_info "Génération de la clé SSH pour la connexion aux clients..."

# Déterminer le répertoire home de l'utilisateur qui a lancé sudo
if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    ACTUAL_USER="root"
    ACTUAL_HOME="/root"
fi

SSH_DIR="$ACTUAL_HOME/.ssh"
SSH_KEY_NAME="monitoring_rsa"
SSH_PRIVATE_KEY="$SSH_DIR/$SSH_KEY_NAME"
SSH_PUBLIC_KEY="$SSH_DIR/${SSH_KEY_NAME}.pub"

# Créer le répertoire .ssh si nécessaire
if [ ! -d "$SSH_DIR" ]; then
    log_info "Création du répertoire $SSH_DIR..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$SSH_DIR"
fi

# Générer la clé SSH si elle n'existe pas déjà
if [ -f "$SSH_PRIVATE_KEY" ]; then
    log_info "Clé SSH existante trouvée : $SSH_PRIVATE_KEY"
    SSH_KEY_EXISTED=true
else
    log_info "Génération d'une nouvelle paire de clés SSH..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_PRIVATE_KEY" -N "" -C "monitoring-system-$(date +%Y%m%d)" >/dev/null 2>&1

    # Définir les bonnes permissions pour securiser
    chmod 600 "$SSH_PRIVATE_KEY"
    chmod 644 "$SSH_PUBLIC_KEY"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$SSH_PRIVATE_KEY"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$SSH_PUBLIC_KEY"

    log_info "Paire de clés SSH générée avec succès"
    SSH_KEY_EXISTED=false
fi

# Lire le contenu de la clé publique
SSH_PUBLIC_KEY_CONTENT=$(cat "$SSH_PUBLIC_KEY")

# Créer le fichier de configuration sécurisé
log_info "Création du fichier de configuration sécurisé : $CONFIG_PATH"

# Créer le répertoire parent si nécessaire
CONFIG_DIR=$(dirname "$CONFIG_PATH")
if [ ! -d "$CONFIG_DIR" ]; then
    log_info "Création du répertoire : $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
    chmod 755 "$CONFIG_DIR"
fi

# Demander le nom d'utilisateur SSH pour la connexion aux clients
echo ""
read -p "Entrez le nom d'utilisateur SSH pour la connexion aux clients (par défaut: $ACTUAL_USER, recommandé : monitoring_user): " SSH_USER_INPUT
SSH_USER="${SSH_USER_INPUT:-$ACTUAL_USER}" # Si l'utilisateur n'entre rien, utiliser ACTUAL_USER

# Créer le fichier de configuration
# CFGEOF 	Pour des fichiers de config
cat > "$CONFIG_PATH" << CFGEOF
# Configuration sécurisée du système de monitoring
# Ce fichier contient des informations sensibles - Permissions: 600

# Connexion à la base de données MariaDB
mariadb_logs_user_password: "$DB_PASSWORD"

# Configuration SSH pour la connexion aux clients
ssh_user: "$SSH_USER"
ssh_priv_key_path: "$SSH_PRIVATE_KEY"
CFGEOF

# Définir les permissions strictes
chmod 600 "$CONFIG_PATH"

# Si exécuté avec sudo, donner la propriété à l'utilisateur réel
if [ -n "$SUDO_USER" ]; then  # -n vérifie si une variable n'est pas vide
    chown "$ACTUAL_USER:$ACTUAL_USER" "$CONFIG_PATH"
else
    chown root:root "$CONFIG_PATH"
fi

log_info "Fichier de configuration créé avec succès avec permissions 600"

# Créer le fichier .env dans le répertoire du projet pour l'application
log_info "Création du fichier .env dans le projet..."

# Déterminer le répertoire du script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # $BASH_SOURCE[0] = le script actuel, dirname retourne le répertoire parent, cd change de répertoire, pwd affiche le répertoire courant.
ENV_FILE="$SCRIPT_DIR/.env"

cat > "$ENV_FILE" << ENVEOF
# Configuration générée automatiquement par setup_database.sh
# Date: $(date '+%Y-%m-%d %H:%M:%S')

# Chemin du fichier de configuration sécurisé
PATH_CONFIG=$CONFIG_PATH
ENVEOF

# Permissions pour .env
chmod 600 "$ENV_FILE"
if [ -n "$SUDO_USER" ]; then
    chown "$ACTUAL_USER:$ACTUAL_USER" "$ENV_FILE"
fi

log_info "Fichier .env créé : $ENV_FILE"

echo ""
echo "============================================"
echo "Configuration terminée avec succès"
echo "============================================"
echo ""
echo "Base de données : logs_db"
echo "Utilisateur     : logs_user"
echo "Mot de passe    : $DB_PASSWORD"
echo "Host            : localhost"
echo ""
echo "Fichier de configuration sécurisé :"
echo "  Chemin      : $CONFIG_PATH"
echo "  Permissions : 600"
echo "  Propriétaire: $ACTUAL_USER"
echo "  Contenu     : mariadb_logs_user_password, ssh_user, ssh_priv_key_path"
echo ""
echo "Tables créées   : roles (3), users (1), servers (0)"
echo "Venv Python     : $VENV_DIR"
echo ""
echo "Utilisateur admin créé :"
echo "  Username : admin"
echo "  Password : admin"
echo "  Role     : admin (tous les privilèges)"
echo ""
echo "IMPORTANT : Changez le mot de passe admin après la première connexion !"
echo ""
echo "Paquets Python installés :"
echo "  - mysql-connector-python"
echo "  - sqlalchemy ~2.0.43"
echo "  - flask ~3.1.2"
echo "  - flask-login ~0.6.3"
echo "  - werkzeug ~3.1.3"
echo "  - pyyaml ~6.0.3"
echo "  - paramiko ~4.0.0"
echo "  - fabric2 ~3.2.2"
echo "  - gunicorn"
echo "  - python-dotenv"
echo ""
echo "Clé SSH pour connexion aux clients :"
if [ "$SSH_KEY_EXISTED" = true ]; then
    echo "  Clé existante utilisée"
else
    echo "  Nouvelle clé générée"
fi
echo "  Clé privée  : $SSH_PRIVATE_KEY"
echo "  Clé publique: $SSH_PUBLIC_KEY"
echo "  Utilisateur : $SSH_USER"
echo ""
echo "============================================"
echo "CLÉ PUBLIQUE SSH À COPIER"
echo "============================================"
echo ""
echo "$SSH_PUBLIC_KEY_CONTENT"
echo ""
echo "============================================"
echo ""
echo "## REMONTEZ AVANT LA CLÉ PRIVÉE SSH POUR INFOS SUR L'INSTALLATION ! ##"
echo ""
echo "IMPORTANT - CONFIGURATION DE L'APPLICATION :"
echo "  1. Le fichier .env a été créé automatiquement dans le projet"
echo "     Il contient : PATH_CONFIG=$CONFIG_PATH"
echo ""
echo "  2. Copiez la clé publique SSH ci-dessus"
echo ""
echo "  3. Sur chaque machine cliente, exécutez :"
echo "     sudo ./setup_client.sh '<clé_publique_ssh>' $SSH_USER"
echo ""
echo "  4. Pour lancer l'application :"
echo "     - Mode développement : python3 run_dev.py"
echo "     - Mode production    : ./run_app.sh"
echo ""
echo "  Note : La configuration est automatique via le fichier .env"
echo "         Aucune modification manuelle n'est nécessaire"
echo ""
echo "Vous pouvez désormais utiliser l'application !"
echo ""

exit 0
