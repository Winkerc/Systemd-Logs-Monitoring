#!/bin/bash

# Script de configuration pour machine cliente - Accès SSH restreint
# Usage: ./setup_client.sh <cle_publique_ssh> [nom_utilisateur]

set -e

# Fonctions d'affichage
log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

show_usage() {
    cat << EOF
Usage: $0 <cle_publique_ssh> [nom_utilisateur]

Arguments:
    <cle_publique_ssh>    Clé publique SSH complète pour l'authentification
                          (doit commencer par ssh-rsa, ssh-ed25519, etc.)

    [nom_utilisateur]     Nom de l'utilisateur qui sera créé sur cette machine
                          pour permettre la connexion SSH et l'exécution des
                          commandes de monitoring (défaut: qamu, recommandé : monitoring_user)

Exemple:
    $0 "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... qamu@server" qamu
    $0 "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... monitoring@central"

Note:
    - Ce script doit être exécuté en tant que root
    - L'utilisateur créé aura des droits sudo restreints pour lire /var/log/syslog
    - Seules certaines commandes SSH seront autorisées (echo test, ls, sudo tail)

EOF
    exit 1
}

# Vérifier root
if [[ $EUID -ne 0 ]]; then
   log_error "Ce script doit être exécuté en tant que root (sudo)"
   exit 1
fi

# Vérifier l'argument
if [ -z "$1" ]; then
    log_error "Clé publique SSH manquante"
    echo ""
    show_usage
fi

SSH_PUBLIC_KEY="$1"
USERNAME="${2:-qamu}"

# Valider le format de la clé SSH
if ! echo "$SSH_PUBLIC_KEY" | grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) "; then
    log_error "Format de clé SSH invalide"
    log_error "La clé doit commencer par: ssh-rsa, ssh-ed25519, ou ecdsa-sha2-*"
    exit 1
fi

log_info "Configuration pour l'utilisateur ${USERNAME}..."
log_info "Machine: $(hostname)"

# Installer sudo si nécessaire
if ! command -v sudo &> /dev/null; then
    log_warn "Installation de sudo..."
    apt-get update -qq && apt-get install -y -qq sudo
fi

# Installer python3 si nécessaire
if ! command -v python3 &> /dev/null; then
    log_warn "Installation de python3..."
    apt-get update -qq && apt-get install -y -qq python3
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
log_info "Création du script de filtre des commandes SSH..."
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
    log_info "Service SSH redémarré avec succès"
else
    log_warn "Redémarrez SSH manuellement: systemctl restart sshd"
fi

# Résumé détaillé
echo ""
echo "============================================"
echo "Configuration terminée avec succès"
echo "============================================"
echo ""
echo "Machine configurée :"
echo "  Hostname     : $(hostname)"
echo "  IP           : $(hostname -I | awk '{print $1}')"
echo ""
echo "Utilisateur SSH créé :"
echo "  Username     : ${USERNAME}"
echo "  Home         : /home/${USERNAME}"
echo "  SSH Key      : Configurée"
echo ""
echo "Test de connexion depuis le serveur central :"
echo "  ssh ${USERNAME}@$(hostname -I | awk '{print $1}') 'echo test'"
echo "  ssh ${USERNAME}@$(hostname -I | awk '{print $1}') 'sudo tail -n 50 /var/log/syslog'"
echo ""

exit 0
