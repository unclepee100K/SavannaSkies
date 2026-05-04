import os
import requests
from datetime import datetime, timedelta
from time import sleep
from flask import Flask, render_template, request, redirect, url_for, session
from dotenv import load_dotenv
from models import db, FavoriteCity

# ---------- Retry helper ----------
def fetch_with_retry(url, params, max_retries=3, timeout=30):
    for attempt in range(max_retries):
        try:
            resp = requests.get(url, params=params, timeout=timeout)
            resp.raise_for_status()
            return resp
        except requests.exceptions.RequestException as e:
            print(f"Attempt {attempt+1} failed: {e}")
            if attempt < max_retries - 1:
                sleep(2)
            else:
                raise
    return None

# ---------- Flask setup ----------
load_dotenv()

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///weather.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.secret_key = 'your-secret-key-change-in-production'
app.permanent_session_lifetime = timedelta(days=7)

db.init_app(app)

with app.app_context():
    db.create_all()

API_KEY = ""
print("DEBUG: API_KEY =", API_KEY[:5] if API_KEY else "MISSING")
BASE_URL = 'https://api.openweathermap.org/data/2.5'

# ---------- Helper functions ----------
def normalize_city_name(city):
    city = city.strip()
    if ',' not in city:
        city += ',ZW'
    return city

def get_weather_condition(description):
    desc = description.lower()
    if 'clear' in desc:
        return 'sunny'
    elif 'cloud' in desc:
        return 'cloudy'
    elif 'rain' in desc or 'drizzle' in desc:
        return 'rainy'
    elif 'thunder' in desc:
        return 'stormy'
    elif 'snow' in desc:
        return 'snowy'
    else:
        return 'default'

def get_current_weather(city_name, units='metric'):
    url = f"{BASE_URL}/weather"
    params = {
        'q': normalize_city_name(city_name),
        'appid': API_KEY,
        'units': units
    }
    try:
        resp = fetch_with_retry(url, params)
        if resp is None:
            raise Exception("Max retries exceeded")
        data = resp.json()
        return {
            'city': data['name'],
            'country': data['sys']['country'],
            'temp': data['main']['temp'],
            'feels_like': data['main']['feels_like'],
            'humidity': data['main']['humidity'],
            'wind_speed': data['wind']['speed'],
            'icon': data['weather'][0]['icon'],
            'description': data['weather'][0]['description'].capitalize(),
            'condition': get_weather_condition(data['weather'][0]['description'])
        }
    except Exception as e:
        print(f"Weather error for {city_name}: {e}")
        return None

def get_5day_forecast(city_name, units='metric'):
    url = f"{BASE_URL}/forecast"
    params = {
        'q': normalize_city_name(city_name),
        'appid': API_KEY,
        'units': units
    }
    try:
        resp = fetch_with_retry(url, params)
        if resp is None:
            raise Exception("Max retries exceeded")
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
    except Exception as e:
        print(f"Forecast error for {city_name}: {e}")
        return [], []

def get_hourly_forecast(city_name, units='metric', hours=12):
    url = f"{BASE_URL}/forecast"
    params = {
        'q': normalize_city_name(city_name),
        'appid': API_KEY,
        'units': units
    }
    try:
        resp = fetch_with_retry(url, params)
        if resp is None:
            raise Exception("Max retries exceeded")
        data = resp.json()
        hourly = []
        now = datetime.now()
        for entry in data['list']:
            dt = datetime.fromtimestamp(entry['dt'])
            if dt > now and len(hourly) < hours // 3:
                hourly.append({
                    'time': dt.strftime('%H:%M'),
                    'temp': round(entry['main']['temp'], 1),
                    'icon': entry['weather'][0]['icon']
                })
        return hourly
    except Exception as e:
        print(f"Hourly error for {city_name}: {e}")
        return []

# ---------- Routes ----------
@app.route('/')
def index():
    # Unit preference
    units = session.get('units', 'metric')
    unit_param = request.args.get('units')
    if unit_param in ['metric', 'imperial']:
        session['units'] = unit_param
        units = unit_param
        return redirect(url_for('index'))

    city = request.args.get('city', 'Harare')

    # Recent searches
    if 'recent' not in session:
        session['recent'] = []
    if city and city not in session['recent']:
        session['recent'].insert(0, city)
        session['recent'] = session['recent'][:5]
        session.modified = True

    weather = get_current_weather(city, units)
    dates, temps = get_5day_forecast(city, units)
    hourly = get_hourly_forecast(city, units, hours=12)
    favorites = FavoriteCity.query.all()

    temp_unit = '°C' if units == 'metric' else '°F'
    wind_unit = 'km/h' if units == 'metric' else 'mph'

    return render_template('index.html',
                           weather=weather,
                           forecast_dates=dates,
                           forecast_temps=temps,
                           hourly=hourly,
                           favorites=favorites,
                           search_city=city,
                           recent=session['recent'],
                           units=units,
                           temp_unit=temp_unit,
                           wind_unit=wind_unit)

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

@app.route('/toggle_units')
def toggle_units():
    current = session.get('units', 'metric')
    session['units'] = 'imperial' if current == 'metric' else 'metric'
    return redirect(request.referrer or url_for('index'))

if __name__ == '__main__':
    app.run(debug=True)
