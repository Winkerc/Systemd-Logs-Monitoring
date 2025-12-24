from app.extensions import db
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import String, Integer, Text
from os import system
import ipaddress
from subprocess import run, TimeoutExpired

class Server(db.Model):
    """Modèle ORM de la table 'servers'."""
    __tablename__ = "servers"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    ip: Mapped[str] = mapped_column(String(45), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=True)


def host_up(hostname, waittime=200):
    """
    Fonction qui faire un ping sur une IP donné pour savoir si la machine est alive ou non.
    Timeout global de 5 secondes.

    :param hostname:
    :param waittime:
    :return:
    """
    assert isinstance(hostname, str), "L'ip/hostname doit etre un str."

    try:
        # On utilise la commande ping du système
        result = run(
            ["ping", "-c", "1", "-W", str(waittime), hostname],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0 #  Si le code de retour est 0, l'hôte est joignable
    except TimeoutExpired:
        return False
    except Exception:
        return False


def server_exist(nom_serv:str) -> bool:
    """Renvoie True/False suivant si le serveur spécifié existe dans la table."""
    return Server.query.filter_by(name=nom_serv).count() > 0

def get_server_by_name(name: str):
    """Renvoie le serveur correspondant au nom spécifié."""
    return Server.query.filter_by(name=name).first()

def get_server_by_id(id: int):
    """Renvoie le serveur correspondant à l'ID spécifié."""
    return Server.query.get(id)

def ip_in_use(ip: str) -> bool:
    """Renvoie True si l'IP est déjà utilisée par un serveur, False sinon."""
    return Server.query.filter_by(ip=ip).count() > 0

def supprime_serv(serv_id:int):
    """Supprime le serveur dont l'ID est spécifié."""
    try :
        serv_id = int(serv_id)

        serv = Server.query.get(serv_id)
        db.session.delete(serv)
        db.session.commit()
        return True
    except:
        return False

def ajoute_server(nom:str, ip:str, desc:str):
    """Ajoute un serveur dans la base de données."""
    try:
        server = Server(name=str(nom), ip=str(ip), description=str(desc))
        db.session.add(server)
        db.session.commit()
        return True
    except:
        return False

def is_ipv4_valide(ip: str) -> bool:
    """
    Retourne True si l'ip est une adresse IPv4 valide, False sinon.
    """
    if not isinstance(ip, str):
        return False
    ip = ip.strip()
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return isinstance(addr, ipaddress.IPv4Address)

def modif_server(id:int,name:str=None, ip:str=None, desc:str=None):
    try:
        id = int(id)

        serv = Server.query.get(id)

        if name :
            serv.name = str(name)
        if ip :
            assert is_ipv4_valide(str(ip))
            serv.ip = str(ip)
        if desc :
            serv.description = str(desc)

        db.session.add(serv)
        db.session.commit()
        return True
    except:
        return False