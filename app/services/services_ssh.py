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


def get_syslog(host:str, lines:int=100, config_path:str="config.yaml") -> tuple:
    """
    Récupère les n dernières lignes du syslog d'un hôte distant via SSH.

    """

    resultat = ""
    cnx = None

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
            connect_kwargs={"key_filename": cfg["ssh_priv_key_path"]}
        )

        result = cnx.run(f"sudo tail -n {lines} /var/log/syslog", hide=True)

        if result.failed:
            resultat = f"Commande échouée (code {result.return_code}). Avez vous bien installé le script sur cette machine ?"
            return resultat, 1

        return result.stdout, 0

    except ssh_exception.NoValidConnectionsError as e:
        resultat = f"Impossible de se connecter à {host}: {e}. Est-elle en ligne ? Le script est-il installé sur cette machine ?"
        return resultat, 1

    except ssh_exception.AuthenticationException as e:
        resultat = f"Échec d'authentification: {e}. Avez vous bien installé le script sur cette machine ?"
        return resultat, 1

    except Exception as e:
        resultat = f"Erreur inattendue: {e}. Avez vous bien installé le script sur cette machine ?"
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