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
    rm -rf "$VENV_DIR"
fi

python3 -m venv "$VENV_DIR"

log_info "Installation du connecteur MySQL dans le venv..."
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet mysql-connector-python

log_info "Environnement Python configuré"

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
echo "Venv Python     : $VENV_DIR"
echo ""
echo "Vous pouvez désormais utiliser l'application en executant le script run_app.sh dans le dossier du projet."
echo ""

exit 0
