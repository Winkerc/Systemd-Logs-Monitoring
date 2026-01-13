from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from app.models import (
    Server, server_exist, ajoute_server, host_up, get_server_by_id,
    is_ipv4_valide, supprime_serv, modif_server, ip_in_use
)

serveurs_bp = Blueprint('serveurs', __name__, url_prefix='/serveurs', template_folder='../templates')


def get_all_servers() -> list:
    """Renvoie la liste de tous les serveurs."""
    return Server.query.all()


@serveurs_bp.route('/', methods=['GET'])
@login_required
def liste():
    """Affiche la liste des serveurs"""
    if not current_user.has_privilege(2):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    servers = get_all_servers()
    return render_template("serveurs.html", servers=servers)


@serveurs_bp.route('/ajouter', methods=['POST'])
@login_required
def ajouter():
    """Ajoute un nouveau serveur"""
    if not current_user.has_privilege(2):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    nom = request.form.get("name")
    ip = request.form.get("ip")
    description = request.form.get("description")

    if nom and ip and description:
        if is_ipv4_valide(ip):
            if not server_exist(nom):
                ajoute_server(nom, ip, description)
                flash(f"Le serveur {nom} a été ajouté avec succès.", "success")
            else:
                flash("Un serveur avec ce nom existe déja.", "warning")
        else:
            flash("L'adresse IP fournie n'est pas valide.", "danger")
    else:
        flash("Tous les champs sont requis.", "danger")

    return redirect(url_for("serveurs.liste"))


@serveurs_bp.route('/<int:server_id>/supprimer', methods=['POST'])
@login_required
def supprimer(server_id):
    """Supprime un serveur"""
    if not current_user.has_privilege(2):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    if supprime_serv(server_id):
        flash("Le serveur a été supprimé avec succès.", "success")
    else:
        flash("Erreur lors de la suppression du serveur.", "danger")

    return redirect(url_for("serveurs.liste"))


@serveurs_bp.route('/<int:server_id>/modifier', methods=['POST'])
@login_required
def modifier(server_id):
    """Modifie un serveur existant"""
    if not current_user.has_privilege(2):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    name_modif = request.form.get("name_modif")
    ip_modif = request.form.get("ip_modif")
    description_modif = request.form.get("description_modif")

    if name_modif or ip_modif or description_modif:
        try:
            server_to_modif = get_server_by_id(server_id)
            nb_err = 0

            # Modification du nom si présent et s'il est différent de l'ancien
            if name_modif and name_modif != server_to_modif.name:
                if not server_exist(str(name_modif)):
                    if not modif_server(server_id, name=str(name_modif)):
                        nb_err += 1
                        flash("Erreur lors de la modification du nom.", "danger")
                else:
                    nb_err += 1
                    flash("Un serveur avec ce nom existe déja.", "danger")

            # Modification de l'ip si présente et si elle est différente de l'ancienne
            if ip_modif and ip_modif != server_to_modif.ip:
                if is_ipv4_valide(str(ip_modif)):
                    if not ip_in_use(str(ip_modif)):
                        if not modif_server(server_id, ip=str(ip_modif)):
                            nb_err += 1
                            flash("Erreur lors de la modification de l'adresse IP.", "danger")
                    else:
                        nb_err += 1
                        flash("L'adresse IP est déjà utilisée par un autre serveur.", "danger")
                else:
                    nb_err += 1
                    flash("L'adresse IP fournie n'est pas valide.", "danger")

            # Modification de la description si présente et si elle est différente de l'ancienne
            if description_modif and description_modif != server_to_modif.description:
                if not modif_server(server_id, desc=str(description_modif)):
                    nb_err += 1
                    flash("Erreur lors de la modification de la description.", "danger")

            if nb_err == 0:
                flash("Le serveur à été modifié avec succès.", "success")

        except Exception as e:
            flash(f"Erreur lors de la modification du serveur : {str(e)}", "danger")

    return redirect(url_for("serveurs.liste"))


@serveurs_bp.route('/<int:server_id>/ping', methods=['POST'])
@login_required
def ping(server_id):
    """Teste la connectivité d'un serveur (ping)"""
    if not current_user.has_privilege(2):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    server = get_server_by_id(server_id)
    if server:
        ip_server = server.ip
        if is_ipv4_valide(ip_server):
            if host_up(ip_server):
                flash(f"Le serveur {ip_server} est joignable.", "success")
            else:
                flash(f"Le serveur {ip_server} n'est pas joignable.", "danger")
        else:
            flash("L'adresse IP n'est pas valide.", "danger")
    else:
        flash("Serveur introuvable.", "danger")

    return redirect(url_for("serveurs.liste"))

