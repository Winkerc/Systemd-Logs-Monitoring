from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_user, logout_user, login_required, current_user
from app.models import User

auth_bp = Blueprint('auth', __name__, template_folder='../templates')


@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    """Page de connexion"""
    # Si il est déja connecté, rediriger
    if current_user.is_authenticated:
        return redirect(url_for('main.index'))

    if request.method == 'POST':
        username = request.form.get("username")
        password = request.form.get("password")
        remember = request.form.get("remember", False)  # checkbox, se souvenir ?

        # On récupere le user
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


@auth_bp.route("/logout")
@login_required
def logout():
    """Déconnexion de l'utilisateur"""
    logout_user()
    flash("Vous avez été déconnecté.", "info")
    return redirect(url_for("auth.login"))

