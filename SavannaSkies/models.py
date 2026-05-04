from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class FavoriteCity(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    city_name = db.Column(db.String(100), unique=True, nullable=False)

    def __repr__(self):
        return f'<FavoriteCity {self.city_name}>'
