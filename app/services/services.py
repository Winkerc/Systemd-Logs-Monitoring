from fabric import Connection
import yaml
import os
from paramiko import ssh_exception
from sys import stderr, exit

def load_config(filename):
    """
    Charge la configuration à partir d'un fichier YAML.
    :param filename: Nom du fichier de configuration YAML.
    :return:
    """
    with open(filename, 'r') as file:
        config = yaml.safe_load(file)
        return config


def get_syslog(host:str, lines:int=100, config_path:str=None) -> tuple:
    """
    Récupère les n dernières lignes du syslog d'un hôte distant via SSH.

    """

    resultat = ""
    cnx = None

    # Si config_path n'est pas fourni, utiliser PATH_CONFIG
    if config_path is None:
        config_path = os.environ.get('PATH_CONFIG')
        if not config_path:
            resultat = "ERREUR : La variable d'environnement 'PATH_CONFIG' n'est pas définie et aucun config_path n'a été fourni."
            return resultat, 1

    # Chargement de la config
    try:
        cfg = load_config(config_path)
    except FileNotFoundError as e:
        resultat = f"Config non trouvée: {e}"
        return resultat, 1
    except Exception as e:
        resultat = f"Erreur config: {e}"
        return resultat, 1

    # Connexion SSH et exécution
    try:
        cnx = Connection(
            host=host,
            user=cfg['ssh_user'],
            connect_kwargs={
                "key_filename": cfg["ssh_priv_key_path"],
                "timeout": 5,  # Timeout de 5 secondes pour la connexion
                "banner_timeout": 5,  # Timeout pour la bannière SSH
                "auth_timeout":5  # Timeout pour l'authentification
            }
        )

        result = cnx.run(f"sudo tail -n {lines} /var/log/syslog", hide=True, timeout=8)

        if result.failed:
            resultat = f"Commande échouée (code {result.return_code}). Avez vous bien installé le script sur cette machine ?"
            return resultat, 1

        return result.stdout, 0

    except TimeoutError as e:
        resultat = f"Timeout lors de la connexion à {host}: impossible de se connecter dans les délais impartis. Vérifiez que le serveur est accessible."
        return resultat, 1

    except ssh_exception.SSHException as e:
        if "timed out" in str(e).lower() or "timeout" in str(e).lower():
            resultat = f"Timeout lors de la connexion SSH à {host}: le serveur ne répond pas. Vérifiez qu'il est en ligne et accessible."
        else:
            resultat = f"Erreur SSH lors de la connexion à {host}: {e}"
        return resultat, 1

    except ssh_exception.NoValidConnectionsError as e:
        resultat = f"Impossible de se connecter à {host}: aucune connexion valide trouvée. Est-elle en ligne ? Le port SSH est-il accessible ?"
        return resultat, 1

    except ssh_exception.AuthenticationException as e:
        resultat = f"Échec d'authentification sur {host}: {e}. Avez vous bien installé le script sur cette machine ?"
        return resultat, 1

    except Exception as e:
        resultat = f"Erreur inattendue lors de la connexion à {host}: {e}"
        return resultat, 1

    finally:
        # Fermer la connexion
        if cnx:
            try:
                cnx.close()
            except:
                pass

"""
logs, exit_code = get_syslog("192.168.122.56", 10, config_path="../../config.yaml")

if exit_code == 0:
    print(logs)

exit(exit_code)

print(get_syslog("192.168.122.56",10))
"""