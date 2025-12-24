from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_user, logout_user, login_required, current_user
from app.models import *
from app.services import *

main = Blueprint('main', __name__, template_folder='../templates')

@main.route('/login', methods=['GET', 'POST'])
def login():
    # si il est déja connecté, rediriger
    if current_user.is_authenticated:
        return redirect(url_for('main.index'))

    if request.method == 'POST':
        username = request.form.get("username")
        password = request.form.get("password")
        remember = request.form.get("remember", False) # checkbox, se souvenir ?

        # on récupere le user
        user = User.query.filter_by(username=username).first()

        # On verifie le mdp
        if user and user.check_password(password):
            login_user(user, remember=remember)
            flash("Connexion réeussie !", "success")

            # On redirige vers la page demandé ou l'index
            next_page = request.args.get("next")
            return redirect(next_page) if next_page else redirect(url_for("main.index"))
        else:
            flash("Échec de la connexion. Vérifiez vos identifiants.", "danger")

    return render_template("login.html")

@main.route("/logout")
@login_required
def logout():
    logout_user()
    flash("Vous avez été déconnecté.", "info")
    return redirect(url_for("main.login"))

@main.route("/")
@login_required
def index():
    return render_template("index.html")

@main.route("/journaux", methods=["GET","POST"])
@login_required
def journaux():
    user = current_user
    if not user.has_privilege(1):  # Vérifie si l'utilisateur n'a pas le privilège de consultation des journaux
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    servers = get_all_servers()
    #logs = get_syslog("192.168.122.106").split("\n")
    logs_servers = []
    if request.method == "POST":
        id_serv_list_select = request.form.getlist("id_serv_select") # ID du serv selectionné
        nb_lignes = request.form.get("nb_lignes") # Nombre de lignes à récupérer

        if nb_lignes == "":
            nb_lignes = "100"
        try :
            nb_lignes = int(nb_lignes)
        except:
            flash("Format du nombre de ligne incorrect, 100 lignes seront affichés.", "danger")
            nb_lignes = 100

        if id_serv_list_select:
            for id_serv in id_serv_list_select:
                serv = None
                try: # On traite le cas où l'id n'est : ou bien pas un entier, ou bien n'existe pas en BDD
                    serv = get_server_by_id(int(id_serv))
                except:
                    flash("Serveur invalide.", "danger")

                if serv: # Si le serveur est trouvé
                    ip_serv = serv.ip

                    result,exit_code = get_syslog(ip_serv, int(nb_lignes))

                    if exit_code == 0:
                        logs_servers.append([serv.name, result.split("\n")[::-1]])
                    else:
                        flash(f"{result}", "danger")
                else:
                    flash("Serveur introuvable.", "danger")

        return render_template("journaux.html", logs_servers=logs_servers, servers=servers)

    return render_template("journaux.html", logs_servers=logs_servers, servers=servers)

@main.route("/serveurs", methods=["GET","POST"])
@login_required
def serveurs():
    user = current_user
    if not user.has_privilege(2):  # Vérifie si l'utilisateur n'a pas le privilège de gestion des serveurs
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    servers = get_all_servers()

    if request.method == "POST":

        # récupération des variables du champ d'ajout de serveurs
        nom_add = request.form.get("name")
        ip_add = request.form.get("ip")
        description_add = request.form.get("description")

        # Récupération des variables du champ de suppression de serveurs et du ping
        del_serv_id = request.form.get("del_serv_id")
        server_id_ping = request.form.get("server_id_ping")

        # Récupération des variables du champ de modification de serveurs
        modif_id_server = request.form.get("modif_id_server")
        name_modif = request.form.get("name_modif")
        ip_modif = request.form.get("ip_modif")
        description_modif = request.form.get("description_modif")

        if nom_add and ip_add and description_add:
            if is_ipv4_valide(ip_add):
                if not server_exist(nom_add):
                    # On ajoute ce serveur dans la BDD
                    ajoute_server(nom_add, ip_add, description_add)
                    flash(f"Le serveur {nom_add} a été ajouté avec succès.", "success")
                else:
                    flash("Un serveur avec ce nom existe déja.", "warning")
            else:
                flash("L'adresse IP fournie n'est pas valide.", "danger")

        if server_id_ping:
            ip_server = get_server_by_id(int(server_id_ping)).ip
            if is_ipv4_valide(ip_server): # On vérifie que l'ip est valide en base de donnée
                if host_up(ip_server):
                    flash(f"Le serveur {ip_server} est joignable.", "success")
                else:
                    flash(f"Le serveur {ip_server} n'est pas joignable.", "danger")
            else:
                flash("L'adresse IP n'est pas valide.", "danger")

        if del_serv_id:
            if supprime_serv(int(del_serv_id)):
                flash(f"Le serveur a été supprimé avec succès.", "success")
            else:
                flash(f"Erreur lors de la suppression du serveur.", "danger")

        if modif_id_server:
            if name_modif or ip_modif or description_modif:

                try:
                    server_to_modif = get_server_by_id(int(modif_id_server))

                    nb_err = 0

                    # On effectue les modifications

                    # Modification du nom si présent et s'il est différent de l'ancien
                    if name_modif and name_modif != server_to_modif.name:
                        if not server_exist(str(name_modif)): # On vérifie qu'aucun serveur n'a ce nom
                            if not modif_server(int(modif_id_server), name=str(name_modif)):
                                nb_err += 1
                                flash("Erreur lors de la modification du nom.", "danger")
                        else:
                            nb_err += 1
                            flash("Un serveur avec ce nom existe déja.", "danger")

                    # Modification de l'ip si présente et si elle est différente de l'ancienne
                    if ip_modif and ip_modif != server_to_modif.ip:
                        if is_ipv4_valide(str(ip_modif)): # On vérifie que l'ip est valide
                            if not ip_in_use(str(ip_modif)): # On vérifie que l'ip n'est pas déjà utilisée
                                if not modif_server(int(modif_id_server), ip=str(ip_modif)):
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
                        if not modif_server(int(modif_id_server, ), desc=str(description_modif)):
                            nb_err += 1
                            flash("Erreur lors de la modification de la description.", "danger")

                    if nb_err == 0:
                        flash(f"Le serveur à été modifié avec succès.", "success")

                except Exception as e:
                    flash(f"Erreur lors de la modification du serveur : {str(e)}", "danger")

        return redirect(url_for("main.serveurs"))

    return render_template("serveurs.html", servers=servers)

@main.route("/utilisateurs", methods=["GET","POST"])
@login_required
def utilisateurs():
    user = current_user
    if not user.has_privilege(4):  # Vérifie si l'utilisateur n'a pas le privilège d'administration des utilisateurs
        flash("Vous n'avez pas les droits nécessaires pour accéder à cette page.", "warning")
        return redirect(url_for("main.index"))

    users = get_all_users()
    roles = get_all_roles()

    if request.method == "POST":

        # récupération des variables du champ d'ajout d'utilisateur
        username = request.form.get("username")
        password = request.form.get("password")
        password_confirm = request.form.get("password_confirm")
        role_id = request.form.get("role_id")

        # récupération des variables du champ de suppression d'utilisateur
        user_id_del = request.form.get("user_id_del")

        # récupération des variables du champ de modification d'utilisateur
        id_user_modif = request.form.get("id_user_modif")
        username_modif = request.form.get("username_modif")
        password_modif = request.form.get("password_modif")
        password_modif_confirm = request.form.get("password_modif_confirm")
        role_id_modif = request.form.get("role_id_modif")

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
                flash(f"La confirmation du mot de passe ne correspond pas.", "danger")

        if user_id_del:
            if int(user_id_del) != int(user.id):
                if supprime_user(int(user_id_del)):
                    flash(f"Utilisateur supprimé avec succès.", "success")
                else:
                    flash(f"Erreur lors de la suppression de l'utilisateur.", "danger")
            else:
                flash(f"Vous ne pouvez pas supprimer votre utilisateur courant !", "danger")

        if id_user_modif:
            if username_modif or password_modif or role_id_modif:

                try:
                    modif_user_target = get_user_by_id(int(id_user_modif))

                    nb_erreur = 0
                    # On effectue les modifications
                    if username_modif and username_modif != modif_user_target.username:
                        if not maj_user(user_id=int(id_user_modif), username=str(username_modif)):
                            flash(f"Erreur lors de la modification du nom d'utilisateur.", "danger")
                            nb_erreur += 1

                    if password_modif :
                        if password_modif == password_modif_confirm:
                            if not maj_user(user_id=int(id_user_modif), password=password_modif):
                                flash(f"Erreur lors de la modification du mot de passe.", "danger")
                                nb_erreur += 1
                        else: # si les deux mots de passe ne correspondent pas
                            flash(f"La confirmation du mot de passe ne correspond pas.", "danger")
                            nb_erreur += 1

                    if role_id_modif and int(role_id_modif) != modif_user_target.role_id:
                        if not maj_user(user_id=int(id_user_modif), role_id=int(role_id_modif)):
                            flash(f"Erreur lors de la modification du rôle.", "danger")
                            nb_erreur += 1

                    if nb_erreur == 0:
                        flash(f"Utilisateur modifié avec succès.", "success")

                except Exception as e:
                    flash(f"Erreur lors de la modification de l'utilisateur : {str(e)}", "danger")

        return redirect(url_for("main.utilisateurs"))

    return render_template("utilisateurs.html", users=users, roles=roles)

def get_all_users()->list:
    """
    Renvoie la liste de tous les utilisateurs, chaque element de la liste est de type User.
    :return:
    """
    return User.query.all()

def get_all_roles()->list:
    """
    Renvoie la liste de tous les rôles, chaque element de la liste est de type Role.
    :return:
    """
    return Role.query.all()

def get_all_servers()->list:
    """
    Renvoie la liste de tous les serveurs, chaque element de la liste est de type Server.
    :return:
    """
    return Server.query.all()


# TODO : Corriger le style de la partie modif d'utilisateur dans utilisateurs.html