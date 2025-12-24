#!/bin/bash

# Script de configuration de la base de données
# Usage: ./setup_database.sh <password>

set -e

log_info() { echo "[INFO] $1"; }
log_error() { echo "[ERROR] $1"; }

show_usage() {
    cat << EOF
Usage: $0 <password>

Arguments:
    <password>    Mot de passe pour l'utilisateur MySQL 'logs_user'
                  Ce mot de passe doit être identique à celui défini
                  dans config.yaml du projet.

Exemple:
    $0 mon_mot_de_passe_securise

Note: Ce script doit être exécuté en tant que root.
      Un utilisateur admin (admin/admin) sera créé automatiquement dans la base de donnée.
EOF
    exit 1
}

if [ $# -ne 1 ]; then
    log_error "Nombre d'arguments incorrect"
    echo ""
    show_usage
fi

DB_PASSWORD="$1"

if [[ $EUID -ne 0 ]]; then
   log_error "Ce script doit être exécuté en tant que root"
   exit 1
fi

log_info "Configuration de la base de données pour le monitoring..."

if ! command -v mysql &> /dev/null; then
    log_info "Installation de MariaDB..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        --no-install-recommends \
        mariadb-server mariadb-client
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

if ! dpkg -l | grep -q python3-venv; then
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
"$VENV_DIR/bin/pip" install --quiet --index-url https://pypi.python.org/simple "fabric2~=3.2.2"

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

if mysql -u root < "$SQL_FILE" 2>&1; then
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

    # Définir les bonnes permissions
    chmod 600 "$SSH_PRIVATE_KEY"
    chmod 644 "$SSH_PUBLIC_KEY"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$SSH_PRIVATE_KEY"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$SSH_PUBLIC_KEY"

    log_info "Paire de clés SSH générée avec succès"
    SSH_KEY_EXISTED=false
fi

# Lire le contenu de la clé publique
SSH_PUBLIC_KEY_CONTENT=$(cat "$SSH_PUBLIC_KEY")

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
echo ""
echo "Clé SSH pour connexion aux clients :"
if [ "$SSH_KEY_EXISTED" = true ]; then
    echo "  Clé existante utilisée"
else
    echo "  Nouvelle clé générée"
fi
echo "  Clé privée  : $SSH_PRIVATE_KEY"
echo "  Clé publique: $SSH_PUBLIC_KEY"
echo ""
echo "============================================"
echo "CLÉ PUBLIQUE SSH À COPIER"
echo "============================================"
echo ""
echo "$SSH_PUBLIC_KEY_CONTENT"
echo ""
echo "============================================"
echo ""
echo "IMPORTANT :"
echo "  1. Copiez la clé publique ci-dessus"
echo "  2. Sur chaque machine cliente, exécutez :"
echo "     sudo ./setup_client.sh <ssh_user> '<clé_publique_ssh>'"
echo "  3. Assurez-vous de mettre à jour config.yaml avec :"
echo "     - ssh_user: <utilisateur_ssh>"
echo "     - ssh_priv_key_path: $SSH_PRIVATE_KEY"
echo ""
echo "Vous pouvez désormais utiliser l'application en exécutant le script run_app.sh dans le dossier du projet."
echo ""

exit 0
