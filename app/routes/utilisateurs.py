from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from app.models import (
    User, Role, ajoute_user, supprime_user, maj_user,
    user_exists, get_user_by_id
)

utilisateurs_bp = Blueprint('utilisateurs', __name__, url_prefix='/utilisateurs', template_folder='../templates')


def get_all_users() -> list:
    """Renvoie la liste de tous les utilisateurs."""
    return User.query.all()


def get_all_roles() -> list:
    """Renvoie la liste de tous les rôles."""
    return Role.query.all()


@utilisateurs_bp.route('/', methods=['GET'])
@login_required
def liste():
    """Affiche la liste des utilisateurs"""
    if not current_user.has_privilege(4):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    users = get_all_users()
    roles = get_all_roles()
    return render_template("utilisateurs.html", users=users, roles=roles)


@utilisateurs_bp.route('/ajouter', methods=['POST'])
@login_required
def ajouter():
    """Ajoute un nouvel utilisateur"""
    if not current_user.has_privilege(4):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    username = request.form.get("username")
    password = request.form.get("password")
    password_confirm = request.form.get("password_confirm")
    role_id = request.form.get("role_id")

    if username and password and role_id:
        if password == password_confirm:
            if user_exists(username):
                flash(f"L'utilisateur {username} existe déjà.", "danger")
            else:
                if ajoute_user(username=username.strip(), password=password, role_id=int(role_id)):
                    flash(f"Utilisateur {username} ajouté avec succès.", "success")
                else:
                    flash(f"Erreur lors de l'ajout de l'utilisateur {username}.", "danger")
        else:
            flash("La confirmation du mot de passe ne correspond pas.", "danger")
    else:
        flash("Tous les champs sont requis.", "danger")

    return redirect(url_for("utilisateurs.liste"))


@utilisateurs_bp.route('/<int:user_id>/supprimer', methods=['POST'])
@login_required
def supprimer(user_id):
    """Supprime un utilisateur"""
    if not current_user.has_privilege(4):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    if int(user_id) != int(current_user.id):
        if supprime_user(user_id):
            flash("Utilisateur supprimé avec succès.", "success")
        else:
            flash("Erreur lors de la suppression de l'utilisateur.", "danger")
    else:
        flash("Vous ne pouvez pas supprimer votre utilisateur courant !", "danger")

    return redirect(url_for("utilisateurs.liste"))


@utilisateurs_bp.route('/<int:user_id>/modifier', methods=['POST'])
@login_required
def modifier(user_id):
    """Modifie un utilisateur existant"""
    if not current_user.has_privilege(4):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    username_modif = request.form.get("username_modif")
    password_modif = request.form.get("password_modif")
    password_modif_confirm = request.form.get("password_modif_confirm")
    role_id_modif = request.form.get("role_id_modif")

    if username_modif or password_modif or role_id_modif:
        try:
            modif_user_target = get_user_by_id(user_id)
            nb_erreur = 0

            # Modification du nom d'utilisateur
            if username_modif and username_modif != modif_user_target.username:
                if not maj_user(user_id=user_id, username=str(username_modif)):
                    flash("Erreur lors de la modification du nom d'utilisateur.", "danger")
                    nb_erreur += 1

            # Modification du mot de passe
            if password_modif:
                if password_modif == password_modif_confirm:
                    if not maj_user(user_id=user_id, password=password_modif):
                        flash("Erreur lors de la modification du mot de passe.", "danger")
                        nb_erreur += 1
                else:
                    flash("La confirmation du mot de passe ne correspond pas.", "danger")
                    nb_erreur += 1

            # Modification du rôle
            if role_id_modif and int(role_id_modif) != modif_user_target.role_id:
                if not maj_user(user_id=user_id, role_id=int(role_id_modif)):
                    flash("Erreur lors de la modification du rôle.", "danger")
                    nb_erreur += 1

            if nb_erreur == 0:
                flash("Utilisateur modifié avec succès.", "success")

        except Exception as e:
            flash(f"Erreur lors de la modification de l'utilisateur : {str(e)}", "danger")

    return redirect(url_for("utilisateurs.liste"))

