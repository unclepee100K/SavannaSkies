import os
import requests
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, jsonify
from dotenv import load_dotenv
from models import db, FavoriteCity

load_dotenv()
API_KEY = "c311270d4cd83f282411da5dc765d1b9"
print("API_KEY loaded:", API_KEY[:5] if API_KEY else "MISSING")

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///weather.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.secret_key = 'your-secret-key-change-in-production'

db.init_app(app)

with app.app_context():
    db.create_all()

API_KEY = os.getenv('OPENWEATHER_API_KEY')
BASE_URL = 'https://api.openweathermap.org/data/2.5'

def normalize_city_name(city):
    city = city.strip()
    if ',' not in city:
        city += ',ZW'
    return city

def get_current_weather(city_name):
    url = f"{BASE_URL}/weather"
    params = {
        'q': normalize_city_name(city_name),
        'appid': "c311270d4cd83f282411da5dc765d1b9",   # hardcoded for test
        'units': 'metric'
    }
    print("Request URL:", requests.Request('GET', url, params=params).prepare().url)  # DEBUG
    try:
        resp = requests.get(url, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        return {
            'city': data['name'],
            'country': data['sys']['country'],
            'temp': data['main']['temp'],
            'feels_like': data['main']['feels_like'],
            'icon': data['weather'][0]['icon'],
            'description': data['weather'][0]['description'].capitalize()
        }
    except Exception as e:
        print(f"Error fetching weather for {city_name}: {e}")
        return None

def get_5day_forecast(city_name):
    url = f"{BASE_URL}/forecast"
    params = {
        'q': normalize_city_name(city_name),
        'appid': API_KEY,
        'units': 'metric'
    }
    try:
        resp = requests.get(url, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        daily_map = {}
        for entry in data['list']:
            dt = datetime.fromtimestamp(entry['dt'])
            date_str = dt.strftime('%Y-%m-%d')
            hour = dt.hour
            temp = entry['main']['temp']
            if date_str not in daily_map or abs(hour - 12) < daily_map[date_str]['hour_diff']:
                daily_map[date_str] = {'temp': temp, 'hour_diff': abs(hour - 12)}
        dates = sorted(daily_map.keys())
        temps = [round(daily_map[d]['temp'], 1) for d in dates]
        return dates[:5], temps[:5]
    except Exception:
        return [], []

@app.route('/')
def index():
    city = request.args.get('city', 'Harare')
    weather = get_current_weather(city)
    dates, temps = get_5day_forecast(city)
    favorites = FavoriteCity.query.all()
    return render_template('index.html', weather=weather, forecast_dates=dates, forecast_temps=temps, favorites=favorites, search_city=city)

@app.route('/add_favorite', methods=['POST'])
def add_favorite():
    city = request.form.get('city_name')
    if city and not FavoriteCity.query.filter_by(city_name=city).first():
        db.session.add(FavoriteCity(city_name=city))
        db.session.commit()
    return redirect(url_for('index', city=city))

@app.route('/delete_favorite/<int:id>')
def delete_favorite(id):
    fav = FavoriteCity.query.get_or_404(id)
    db.session.delete(fav)
    db.session.commit()
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True)
