import os
from app.services import load_config

cfg = load_config("config.yaml")
password = cfg['mariadb_logs_user_password']

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-key-change-in-production-123456'
    REMEMBER_COOKIE_DURATION = 3600

    SQLALCHEMY_DATABASE_URI = f'mysql+pymysql://logs_user:{password}@localhost/logs_db'
    SQLALCHEMY_ENGINE_OPTIONS = {
        'pool_pre_ping': True,
        'pool_recycle': 3600,
        'pool_size': 10,
    }