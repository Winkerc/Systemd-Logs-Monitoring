from app.extensions import db
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Boolean, ForeignKey
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from sqlalchemy import String, Integer

class User(db.Model, UserMixin):
    """Modèle ORM de la table 'users'."""
    __tablename__ = "users"
    # __table_args__ = {'extend_existing': True} # Pour éviter les conflits si la table est déjà définie ailleurs

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement="auto")
    username: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    role_id: Mapped[int] = mapped_column(Integer, ForeignKey('roles.id'), default=False)

    # Relation : un utilisateur a un rôle
    role: Mapped["Role"] = relationship("Role", back_populates="users")

    def set_password(self, password: str):
        """Hash le mot de passe."""
        assert isinstance(password, str)
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        """Vérifie le mot de passe."""
        assert isinstance(password, str)
        return check_password_hash(self.password_hash, password)

    def has_privilege(self, privilege_bit: int) -> bool:
        """Vérifie si l'utilisateur a un privilège via son rôle."""
        assert isinstance(privilege_bit, int)
        assert 0 <= privilege_bit <= 7
        return bool(self.role.privileges & privilege_bit) # Opération bitwise AND


def ajoute_user(username:str, password:str, role_id:int=1):
    """Ajoute un utilisateur dans la base de données."""
    try:
        user = User(username=str(username), role_id=str(role_id))
        user.set_password(str(password))
        db.session.add(user)
        db.session.commit()
        return True
    except:
        return False


def supprime_user(user_id:int):
    """Supprime un utilisateur de la base de données."""
    try :
        user_id = int(user_id)

        user = User.query.get(user_id)
        db.session.delete(user)
        db.session.commit()
        return True
    except:
        return False

def maj_user(user_id:int, username:str=None, password:str=None, role_id:int=None):
    """Met à jour un utilisateur dans la base de données."""
    try:
        user_id = int(user_id)

        user = User.query.get(user_id)
        if username:
            user.username = str(username)
        if password:
            user.set_password(str(password))
        if role_id is not None:
            assert isinstance(role_id, int)
            user.role_id = role_id
        db.session.add(user)
        db.session.commit()
        return True
    except:
        return False


def get_user_by_username(username: str):
    """Récupère un utilisateur par son nom."""
    return User.query.filter_by(username=str(username)).first()

def get_user_by_id(user_id: int):
    """Récupère un utilisateur par son ID."""
    return User.query.get(user_id)

def user_exists(username: str) -> bool:
    """Vérifie si un utilisateur existe."""
    try :
        return User.query.filter_by(username=str(username)).count() > 0
    except:
        return False