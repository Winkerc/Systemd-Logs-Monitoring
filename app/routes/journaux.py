from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from app.models import Server, get_server_by_id
from app.services import get_syslog
from datetime import datetime

journaux_bp = Blueprint('journaux', __name__, url_prefix='/journaux', template_folder='../templates')


def get_all_servers() -> list:
    """Renvoie la liste de tous les serveurs."""
    return Server.query.all()


def extract_timestamp(log_line):
    """
    Extrait et parse le timestamp d'une ligne de log.
    :param log_line: Ligne de log
    :return: datetime
    """
    try:
        timestamp_str = log_line.split()[0]
        # Parser avec timezone
        dt = datetime.fromisoformat(timestamp_str)
        # Retirer la timezone (convert to naive datetime)
        return dt.replace(tzinfo=None)
    except (ValueError, IndexError):
        return datetime.min


@journaux_bp.route('/', methods=['GET'])
@login_required
def liste():
    """Affiche la page des journaux"""
    if not current_user.has_privilege(1):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    servers = get_all_servers()
    return render_template("journaux.html", all_logs=[], servers=servers)


@journaux_bp.route('/charger', methods=['POST'])
@login_required
def charger():
    """Charge les logs des serveurs sélectionnés"""
    if not current_user.has_privilege(1):
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    servers = get_all_servers()
    logs_servers = []
    all_logs = []

    id_serv_list_select = request.form.getlist("id_serv_select")  # ID des serveurs sélectionnés
    nb_lignes = request.form.get("nb_lignes")  # Nombre de lignes à récupérer

    if nb_lignes == "":
        nb_lignes = "100"
    try:
        nb_lignes = int(nb_lignes)
    except:
        flash("Format du nombre de ligne incorrect, 100 lignes seront affichées.", "danger")
        nb_lignes = 100

    if id_serv_list_select:
        for id_serv in id_serv_list_select:
            serv = None
            try:
                serv = get_server_by_id(int(id_serv))
            except:
                flash("Serveur invalide.", "danger")

            if serv:
                ip_serv = serv.ip
                result, exit_code = get_syslog(ip_serv, int(nb_lignes))

                if exit_code == 0:
                    logs_servers.append([serv.name, result.split("\n")[::-1]])
                else:
                    flash(f"{result}", "danger")
            else:
                flash("Serveur introuvable.", "danger")

        for server_name, logs in logs_servers:
            for log in logs:
                if log != "":
                    all_logs.append({
                        'server': server_name,
                        'line': log,
                        'timestamp': extract_timestamp(log)
                    })

        all_logs.sort(key=lambda x: x['timestamp'])

    return render_template("journaux.html", all_logs=all_logs, servers=servers)

