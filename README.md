# Système de Monitoring de Logs

Application web Flask pour la consultation centralisée des logs système de plusieurs serveurs via SSH.

## Table des matières

1. [Fonctionnalités](#fonctionnalités)
2. [Architecture](#architecture)
3. [Prérequis](#prérequis)
   - [Serveur de Monitoring](#serveur-de-monitoring)
   - [Machines Clientes](#machines-clientes)
4. [Installation](#installation)
   - [Installation sur le Serveur de Monitoring](#installation-sur-le-serveur-de-monitoring)
   - [Configuration du fichier config.yaml](#configuration-du-fichier-configyaml)
   - [Installation sur les Machines Clientes](#installation-sur-les-machines-clientes)
5. [Utilisation](#utilisation)
   - [Démarrer le Serveur](#démarrer-le-serveur)
   - [Première Connexion](#première-connexion)
   - [Ajouter un Serveur](#ajouter-un-serveur)
   - [Consulter les Logs](#consulter-les-logs)
   - [Gérer les Utilisateurs](#gérer-les-utilisateurs)
6. [Système de Permissions](#système-de-permissions)
7. [Dépannage](#dépannage)
   - [Problème : "Timeout lors de la connexion SSH"](#problème--timeout-lors-de-la-connexion-ssh)
   - [Problème : "Échec d'authentification"](#problème--échec-dauthentification)
   - [Problème : Erreur de connexion à la base de données](#problème--erreur-de-connexion-à-la-base-de-données)
   - [Problème : Port 5000 déjà utilisé](#problème--port-5000-déjà-utilisé)
8. [Structure du Projet](#-structure-du-projet)
9. [Configuration Avancée](#configuration-avancée)
   - [Augmenter le nombre de workers Gunicorn](#augmenter-le-nombre-de-workers-gunicorn)
10. [Surveillance et Logs](#-surveillance-et-logs)
    - [Logs Gunicorn](#logs-gunicorn)
    - [Logs de l'application Flask](#logs-de-lapplication-flask)
11. [Mise à jour](#mise-à-jour)
12. [Technologies utilisées](#technologies-utilisées)
13. [Notes de Sécurité](#notes-de-sécurité)

---

## Fonctionnalités

- Consultation des logs système (`/var/log/syslog`) de plusieurs serveurs simultanément
- Tri chronologique automatique des logs multi-serveurs
- Interface web intuitive avec gestion des utilisateurs et des rôles
- Authentification sécurisée par clé SSH
- Gestion des serveurs (ajout, modification, suppression, test de connexion)
- Système de permissions (utilisateur, gestionnaire, admin)
- Serveur de production avec Gunicorn

## Architecture

```
┌─────────────────────────────────────┐
│   Serveur de Monitoring (Flask)     │
│   - Interface Web                   │
│   - Base de données MySQL           │
│   - Connexions SSH                  │
└──────────────┬──────────────────────┘
               │ SSH (clé publique/privée)
               │
    ┌──────────┴──────────┬──────────────┐
    │                     │              │
┌───▼────┐          ┌────▼───┐      ┌───▼────┐
│ Client │          │ Client │      │ Client │
│   1    │          │   2    │      │   3    │
└────────┘          └────────┘      └────────┘
```

## Prérequis

### Serveur de Monitoring
- **OS** : Linux (Debian/Ubuntu recommandé)
- **Accès root** : Pour l'installation

### Machines Clientes
- **OS** : Linux avec `systemd`
- **Accès root** : Pour la configuration SSH
- **Logs** : `/var/log/syslog` accessible

## Installation

### Installation sur le Serveur de Monitoring

```bash
# Cloner ou copier le projet
cd /path/to/project

# Rendre les scripts exécutables
chmod +x setup_database.sh run_app.sh

# Lancer l'installation
# Option 1 : Utiliser le chemin par défaut (/etc/monitoring/config.yaml)
sudo ./setup_database.sh mot_de_passe

# Option 2 : Spécifier un chemin personnalisé
sudo ./setup_database.sh /opt/monitoring/config.yaml mot_de_passe
```

**Ce script va effectuer les actions suivantes :**

- Installer MariaDB et Python 3
- Créer un environnement virtuel Python dans `/opt/monitoring_venv`
- Installer toutes les dépendances (Flask, SQLAlchemy, Paramiko, Fabric2, Gunicorn...)
- Créer la base de données `logs_db` avec les tables nécessaires
- Créer un utilisateur admin par défaut (admin/admin)
- Générer automatiquement une paire de clés SSH (`~/.ssh/monitoring_rsa`)
- **Créer le fichier de configuration sécurisé** contenant :
  - Le mot de passe MariaDB
  - L'utilisateur SSH
  - Le chemin de la clé privée SSH
- Afficher la clé publique SSH à copier

**Notes importantes :**

1. **Fichier de configuration sécurisé** : Le script crée automatiquement un fichier `config.yaml` dans le répertoire spécifié (par défaut `/etc/monitoring/config.yaml`) avec des permissions 600 pour protéger les informations sensibles.

2. **Fichier .env** : Le script crée automatiquement un fichier `.env` dans le répertoire du projet contenant la variable `PATH_CONFIG` qui pointe vers le fichier de configuration sécurisé. Ce fichier est chargé automatiquement par l'application.

3. **Utilisateur SSH** : Le script vous demandera de saisir le nom d'utilisateur SSH qui sera utilisé pour se connecter aux machines clientes (par défaut : votre nom d'utilisateur actuel).

4. **Clé publique SSH** : À la fin du script, copiez la clé publique SSH affichée, vous en aurez besoin pour les clients.

### Configuration de l'application

**Configuration automatique** : Après l'installation, la configuration est **automatique** ! Le fichier `.env` créé par `setup_database.sh` contient déjà le bon chemin vers le fichier de configuration sécurisé.

**Si vous avez besoin de modifier le chemin** (rare) :
```bash
# Éditez le fichier .env
nano .env

# Modifiez la ligne :
PATH_CONFIG=/votre/chemin/personnalisé/config.yaml
```

**Note de sécurité :**
- Le vrai fichier de configuration avec les credentials est stocké de manière sécurisée (permissions 600).

### Installation sur les Machines Clientes

Sur **chaque machine** que vous souhaitez monitorer :

```bash
# Copier le script setup_client.sh sur la machine cliente
scp setup_client.sh user@ip:/tmp/

# Se connecter à la machine cliente
ssh user@ip

# Rendre le script exécutable
chmod +x /tmp/setup_client.sh

# Lancer l'installation (remplacer par votre clé publique et nom d'utilisateur)
sudo /tmp/setup_client.sh monitoring_user 'ssh-rsa AAAAB3NzaC1yc2E...'
```
**⚠️Important⚠️ :** 
- Remplacez `monitoring_user` par le nom d'utilisateur SSH que vous avez défini lors de l'installation du serveur (celui que vous avez saisi quand setup_database.sh vous l'a demandé)
- Remplacez `'ssh-rsa AAAAB3NzaC1yc2E...'` par la clé publique SSH complète affichée à la fin de setup_database.sh
- Cet utilisateur **doit être le même** que celui défini dans le fichier de configuration sécurisé

**Ce script va effectuer les actions suivantes :**
- Créer l'utilisateur SSH spécifié
- Configurer les permissions sudo pour lire `/var/log/syslog`
- Ajouter la clé publique SSH dans `~/.ssh/authorized_keys`
- Sécuriser la connexion SSH

## Utilisation

### Démarrer le Serveur

```bash
cd /path/to/SAE302
./run_app.sh
```

Le serveur démarre sur **http://0.0.0.0:5000**

### Première Connexion

1. Ouvrez votre navigateur : `http://votre_serveur:5000`
2. Connectez-vous avec :
   - **Username** : `admin`
   - **Password** : `admin`
3. **IMPORTANT** : Changez immédiatement le mot de passe admin

### Ajouter un Serveur

1. Aller dans **Serveurs**
2. Remplir le formulaire :
   - **Nom** : Nom identifiant du serveur
   - **IP** : Adresse IP
   - **Description** : Description libre
3. Cliquer sur **Ajouter**
4. Tester la connexion avec le bouton **Tester**

### Consulter les Logs

1. Aller dans **Journaux**
2. Sélectionner un ou plusieurs serveurs (Ctrl + clic)
3. Indiquer le nombre de lignes à afficher (100 par défaut)
4. Cliquer sur **Afficher les logs**

**Fonctionnalités :**
- Les logs de plusieurs serveurs sont triés chronologiquement
- Affichage coloré
- Timeout de connexion : 5 secondes

### Gérer les Utilisateurs

1. Aller dans **Utilisateurs** (accès admin requis)
2. Ajouter un utilisateur avec son rôle :
   - **Utilisateur** : Lecture seule des logs
   - **Gestionnaire** : Gestion des serveurs + consultation
   - **Admin** : Tous les privilèges

## Système de Permissions

| Rôle | Privilèges | Description |
|------|-----------|-------------|
| **Utilisateur** | 1 | Consultation des journaux uniquement |
| **Gestionnaire** | 3 | Consultation + Gestion des serveurs |
| **Admin** | 7 | Tous les privilèges + Gestion des utilisateurs |

## Dépannage

### Problème : "Timeout lors de la connexion SSH"

**Causes possibles :**
- Le serveur client est éteint ou inaccessible
- Le port SSH (22) est bloqué par un firewall
- L'utilisateur SSH n'existe pas sur le client

**Solutions :**
```bash
# Vérifier la connectivité
ping adresse_ip_client

# Tester la connexion SSH manuellement
ssh -i ~/.ssh/monitoring_rsa monitoring_user@adresse_ip_client

# Vérifier le firewall
sudo ufw status
```

### Problème : "Échec d'authentification"

**Cause :** La clé publique n'est pas correctement installée sur le client

**Solution :**
```bash
# Sur le client, vérifier les permissions
ls -la /home/monitoring_user/.ssh/
# Doit être : drwx------ (700) pour .ssh
#             -rw------- (600) pour authorized_keys

# Vérifier le contenu de authorized_keys
sudo cat /home/monitoring_user/.ssh/authorized_keys
```

### Problème : Erreur de connexion à la base de données

**Solutions :**
```bash
# Vérifier que MariaDB est démarré
sudo systemctl status mariadb

# Tester la connexion
mysql -u logs_user -p logs_db

# Vérifier que PATH_CONFIG est défini
echo $PATH_CONFIG

# Vérifier que le fichier de config existe
cat $PATH_CONFIG

# Vérifier les permissions du fichier
ls -l $PATH_CONFIG
# Doit être : -rw------- (600)
```

### Problème : Port 5000 déjà utilisé

**Solution :** Modifier le port dans `run_app.sh` :
```bash
# Changer -b 0.0.0.0:5000 par -b 0.0.0.0:8080
```

## Structure du Projet

```
SAE302/
├── app/                          # Application Flask
│   ├── __init__.py              
│   ├── extensions.py            # Extensions Flask (db, login_manager)
│   ├── models/                  # Modèles SQLAlchemy
│   │   ├── user.py             # Modèle User
│   │   ├── role.py             # Modèle Role
│   │   └── server.py           # Modèle Server
│   ├── routes/                  # Routes Flask
│   │   └── routes.py           # Toutes les routes
│   ├── services/                # Services gestion
│   │   └── services_ssh.py     # Connexion SSH et récupération logs
│   ├── static/                  # Fichiers statiques
│   │   └── style.css           # CSS de l'interface
│   └── templates/               # Templates
│       ├── index.html          # Template de base
│       ├── login.html          # Page de connexion
│       ├── serveurs.html       # Gestion des serveurs
│       ├── utilisateurs.html   # Gestion des utilisateurs
│       └── journaux.html       # Consultation des logs
├── config.py                    # Chargement configurations (utilise PATH_CONFIG)
├── .env                         # Variables d'environnement (créé par setup_database.sh)
├── .gitignore                   # Fichiers à ignorer (inclut config.yaml et .env)
├── run_dev.py                   # Point d'entrée Flask (dev)
├── run_app.sh                   # Script de lancement (Gunicorn, prod)
├── setup_database.sh            # Installation serveur + génération config sécurisé
├── setup_client.sh              # Installation client
└── README.md                    # Documentation
```

## Configuration Avancée

### Augmenter le nombre de workers Gunicorn

Éditez `run_app.sh` :
```bash
# Nombre de workers :
-w 4  # Pour 4 workers
-w 8  # Pour 8 workers
```

##  Surveillance et Logs

### Logs Gunicorn
```bash
# Logs en temps réel
./run_app.sh

# Logs avec systemd
sudo journalctl -u monitoring.service -f
```

### Logs de l'application Flask
Les logs Flask sont intégrés aux logs Gunicorn (stdout/stderr).

## Mise à jour

```bash
# Arrêter le serveur : Ctrl+C

# Mettre à jour le code
git pull  # ou copier les nouveaux fichiers

# Relancer
./run_app.sh
# Si systemd : sudo systemctl start monitoring.service
```

## Technologies utilisées

- **Backend** : Flask 3.1.2, SQLAlchemy 2.0.43
- **SSH** : Paramiko 4.0.0, Fabric2 3.2.2
- **Base de données** : MariaDB/MySQL
- **Serveur** : Gunicorn (production)
- **Frontend** : HTML5, CSS3, Jinja2

## Notes de Sécurité

### Recommandations

1. **Changez le mot de passe admin** après la première connexion
2. **Utilisez HTTPS** avec un certificat SSL (Let's Encrypt)
3. **Protégez les clés SSH** :
   ```bash
   chmod 600 ~/.ssh/monitoring_rsa
   chmod 644 ~/.ssh/monitoring_rsa.pub
   ```
4. **Protégez le fichier de configuration sécurisé** :
   ```bash
   # Vérifier les permissions (doit être 600)
   ls -l /etc/monitoring/config.yaml
   
   # Corriger si nécessaire
   sudo chmod 600 /etc/monitoring/config.yaml
   ```
5. **Ne commitez jamais** le fichier `config.yaml` avec des credentials réels (il est dans `.gitignore`)
6. **Limitez l'accès SSH** sur les clients uniquement à l'IP du serveur de monitoring
7. **Sauvegardez régulièrement** la base de données :
   ```bash
   mysqldump -u logs_user -p logs_db > backup_$(date +%Y%m%d).sql
   ```

### Architecture de Sécurité

- **Séparation des credentials** : Le fichier de configuration avec les mots de passe est stocké hors du projet (par défaut `/etc/monitoring/config.yaml`)
- **Permissions strictes** : Le fichier de configuration a des permissions 600 (lecture/écriture uniquement pour le propriétaire)
- **Fichier .env** : Contient uniquement le chemin vers le fichier de configuration, pas de credentials
- **Git ignore** : Les fichiers `config.yaml` et `.env` sont ignorés par Git pour éviter les commits accidentels
- **Configuration automatique** : Le fichier `.env` est créé automatiquement par `setup_database.sh` avec le bon chemin

---


