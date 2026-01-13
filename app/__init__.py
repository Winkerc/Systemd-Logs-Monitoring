from flask import Flask
from config import Config
from app.routes import blueprints  # Importer la liste des blueprints
from app.extensions import db, login_manager

def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    db.init_app(app)
    login_manager.init_app(app)

    login_manager.login_view = 'auth.login'
    login_manager.login_message = "Veuillez vous connecter pour accéder à cette page."
    login_manager.login_message_category = "info"

    @login_manager.user_loader
    def load_user(user_id):
        from app.models import User
        return User.query.get(int(user_id))

    # Enregistrer tous les blueprints
    for blueprint in blueprints:
        app.register_blueprint(blueprint)

    return app
