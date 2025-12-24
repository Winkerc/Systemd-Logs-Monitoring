from app.extensions import db
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Integer

class Role(db.Model):
    __tablename__ = 'roles'
    #__table_args__ = {'extend_existing': True}  # Pour éviter les conflits si la table est déjà définie ailleurs

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    description: Mapped[str] = mapped_column(String(50), nullable=False)
    privileges: Mapped[int] = mapped_column(Integer, nullable=False)

    # Relation inverse : un rôle peut avoir plusieurs utilisateurs
    users: Mapped[list["User"]] = relationship("User", back_populates="role")

    def has_privilege(self, privilege_bit):
        """Vérifie si le rôle possède un privilège donné"""
        # On utilise une opération bitwise AND (&) pour tester si le bit correspondant est activé.
        return bool(self.privileges & privilege_bit)


# Constantes pour les privilèges
PRIVILEGE_CONSULTATION = 1  # bit 1
PRIVILEGE_GESTION_SERVEURS = 2  # bit 2
PRIVILEGE_ADMIN_USERS = 4  # bit 4
