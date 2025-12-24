#!/bin/bash

# Script de configuration pour machine cliente - Accès SSH restreint
# Usage: ./setup_client.sh <cle_publique_ssh> [nom_utilisateur]

set -e

# Fonctions d'affichage
log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

# Vérifier root
if [[ $EUID -ne 0 ]]; then
   log_error "Ce script doit être exécuté en tant que root"
   exit 1
fi

# Vérifier l'argument
if [ -z "$1" ]; then
    log_error "Usage: $0 <cle_publique_ssh> [nom_utilisateur]"
    exit 1
fi

SSH_PUBLIC_KEY="$1"
USERNAME="${2:-qamu}"

log_info "Configuration pour l'utilisateur ${USERNAME}..."

# Installer sudo si nécessaire
if ! command -v sudo &> /dev/null; then
    log_warn "Installation de sudo..."
    apt-get update && apt-get install -y sudo
fi

# Installer python3 si nécessaire
if ! command -v python3 &> /dev/null; then
    log_warn "Installation de python3..."
    apt-get update && apt-get install -y python3
fi

# Créer l'utilisateur
if ! id "$USERNAME" &> /dev/null; then
    log_info "Création de l'utilisateur ${USERNAME}..."
    useradd -m -s /bin/bash "$USERNAME"
else
    log_warn "L'utilisateur ${USERNAME} existe déjà"
fi

# Configuration sudo
log_info "Configuration de sudo..."
mkdir -p /etc/sudoers.d
echo "${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/tail -n * /var/log/syslog" > /etc/sudoers.d/${USERNAME}
chmod 0440 /etc/sudoers.d/${USERNAME}

# Créer le script de filtre
log_info "Création du script de filtre..."
cat > /usr/local/bin/filter_ssh_commands_${USERNAME}.py << 'EOF'
#!/usr/bin/env python3
import sys
import os
import re

original_command = os.environ.get('SSH_ORIGINAL_COMMAND')

if original_command is None:
    sys.stderr.write("Pas de commande SSH\n")
    sys.exit(1)

allowed = ["echo test", "ls"]
allowed_regex = [r"sudo tail -n .* /var/log/syslog"]

if original_command in allowed:
    os.system(original_command)
    sys.exit(0)

for elem in allowed_regex:
    if re.match(elem, original_command):
        os.system(original_command)
        sys.exit(0)

sys.stderr.write(f"Commande non autorisee: {original_command}\n")
sys.exit(1)
EOF

chmod +x /usr/local/bin/filter_ssh_commands_${USERNAME}.py

# Configuration SSH
log_info "Configuration de la clé SSH..."
SSH_DIR="/home/${USERNAME}/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

AUTH_KEYS="${SSH_DIR}/authorized_keys"
echo "command=\"/usr/local/bin/filter_ssh_commands_${USERNAME}.py\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ${SSH_PUBLIC_KEY}" > "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# Changer le propriétaire
chown -R ${USERNAME}:${USERNAME} "$SSH_DIR"

# Activer PubkeyAuthentication
log_info "Configuration du serveur SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
if ! grep -q "^PubkeyAuthentication yes" "$SSHD_CONFIG"; then
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
fi

# Redémarrer SSH
log_info "Redémarrage du service SSH..."
if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
    log_info "Service SSH redémarré"
else
    log_warn "Redémarrez SSH manuellement: systemctl restart sshd"
fi

# Résumé
echo ""
log_info "Configuration terminée avec succès!"
echo ""
echo "Utilisateur : ${USERNAME}"
echo "Hostname    : $(hostname)"
echo "IP          : $(hostname -I | awk '{print $1}')"
echo ""
echo "Test : ssh ${USERNAME}@\$(hostname -I | awk '{print \$1}') 'echo test'"
echo ""

exit 0
