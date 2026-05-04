# ============================================
# ENHANCE WEATHER APP WITH ALL FEATURES
# ============================================

Write-Host "📦 Backing up current files..." -ForegroundColor Cyan
Copy-Item app.py app_backup.py -ErrorAction SilentlyContinue
Copy-Item templates/index.html templates/index_backup.html -ErrorAction SilentlyContinue

Write-Host "✨ Creating enhanced app.py..." -ForegroundColor Cyan

$newAppPy = @'
import os
import requests
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, session, jsonify
from dotenv import load_dotenv
from models import db, FavoriteCity

load_dotenv()

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///weather.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.secret_key = 'your-secret-key-change-in-production'
app.permanent_session_lifetime = timedelta(days=7)

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

def get_weather_condition(description):
    """Return background class based on weather description"""
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
        resp = requests.get(url, params=params, timeout=10)
        resp.raise_for_status()
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
        print(f"Weather error: {e}")
        return None

def get_5day_forecast(city_name, units='metric'):
    url = f"{BASE_URL}/forecast"
    params = {
        'q': normalize_city_name(city_name),
        'appid': API_KEY,
        'units': units
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

def get_hourly_forecast(city_name, units='metric', hours=12):
    """Return next N hours (3-hour steps)"""
    url = f"{BASE_URL}/forecast"
    params = {
        'q': normalize_city_name(city_name),
        'appid': API_KEY,
        'units': units
    }
    try:
        resp = requests.get(url, params=params, timeout=10)
        resp.raise_for_status()
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
    except Exception:
        return []

@app.route('/')
def index():
    # Unit preference (metric/imperial) stored in session
    units = session.get('units', 'metric')
    unit_param = request.args.get('units')
    if unit_param in ['metric', 'imperial']:
        session['units'] = unit_param
        units = unit_param
        # Redirect to remove query param
        return redirect(url_for('index'))

    city = request.args.get('city', 'Harare')

    # Recent searches (store in session)
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

    # Unit symbol
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
'@

# Add missing timedelta import at top
$newAppPy = $newAppPy -replace 'from datetime import datetime', 'from datetime import datetime, timedelta'

$newAppPy | Out-File -FilePath app.py -Encoding utf8

Write-Host "✅ app.py updated with all features" -ForegroundColor Green

Write-Host "🎨 Creating enhanced index.html..." -ForegroundColor Cyan

$newIndexHtml = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Zimbabwe Weather</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        /* Dynamic background classes */
        body.sunny { background: linear-gradient(135deg, #f9d423, #ff4e50); }
        body.cloudy { background: linear-gradient(135deg, #757f9a, #d7dde8); }
        body.rainy { background: linear-gradient(135deg, #2c3e50, #3498db); }
        body.stormy { background: linear-gradient(135deg, #141e30, #243b55); }
        body.snowy { background: linear-gradient(135deg, #e6e9f0, #eef2f3); }
        body.default { background: linear-gradient(135deg, #0f2027, #203a43, #2c5364); }

        .hourly-card {
            transition: all 0.2s ease;
        }
        .hourly-card:hover {
            transform: translateY(-5px);
        }
        .recent-btn {
            transition: all 0.2s;
        }
        .recent-btn:hover {
            background-color: rgba(255,255,255,0.3);
        }
    </style>
</head>
<body class="{{ weather.condition if weather else 'default' }} text-white min-h-screen transition-all duration-500">
    <div class="container mx-auto px-4 py-8 max-w-6xl">
        <div class="flex justify-end mb-4">
            <a href="{{ url_for('toggle_units') }}" class="bg-white/20 hover:bg-white/30 px-4 py-2 rounded-full text-sm font-semibold backdrop-blur-sm transition">
                Switch to {{ '°F' if units == 'metric' else '°C' }}
            </a>
        </div>
        <div class="flex flex-col md:flex-row gap-6">
            <!-- Sidebar -->
            <aside class="md:w-1/4 bg-white/10 backdrop-blur-md rounded-2xl p-5 shadow-xl h-fit">
                <h2 class="text-xl font-bold mb-4 border-b border-white/30 pb-2">⭐ Favorite Cities</h2>
                <ul class="space-y-2">
                    {% for fav in favorites %}
                    <li class="flex justify-between items-center">
                        <a href="{{ url_for('index', city=fav.city_name) }}" class="hover:underline text-lg">{{ fav.city_name }}</a>
                        <a href="{{ url_for('delete_favorite', id=fav.id) }}" class="text-red-300 hover:text-red-100 text-sm">🗑️</a>
                    </li>
                    {% else %}
                    <li class="text-white/70">No favorites yet.</li>
                    {% endfor %}
                </ul>
                <form action="{{ url_for('add_favorite') }}" method="post" class="mt-5">
                    <input type="text" name="city_name" placeholder="City name (e.g., Bulawayo)" class="w-full p-2 rounded-lg text-black mb-2" required>
                    <button type="submit" class="bg-blue-500 hover:bg-blue-600 w-full py-2 rounded-lg transition">➕ Add</button>
                </form>

                {% if recent %}
                <h2 class="text-xl font-bold mt-6 mb-3 border-b border-white/30 pb-2">🕒 Recent</h2>
                <div class="flex flex-wrap gap-2">
                    {% for city in recent %}
                    <a href="{{ url_for('index', city=city) }}" class="recent-btn bg-white/20 px-3 py-1 rounded-full text-sm hover:bg-white/30">{{ city }}</a>
                    {% endfor %}
                </div>
                {% endif %}
            </aside>

            <!-- Main Dashboard -->
            <main class="md:w-3/4 space-y-6">
                <form method="get" action="/" class="flex gap-2">
                    <input type="text" name="city" placeholder="Search city in Zimbabwe..." value="{{ search_city }}" class="flex-1 p-3 rounded-xl text-black text-lg">
                    <button type="submit" class="bg-emerald-500 hover:bg-emerald-600 px-6 rounded-xl transition font-bold">🔍 Search</button>
                </form>

                {% if weather %}
                <div class="bg-white/20 backdrop-blur-md rounded-2xl p-6 shadow-xl transition hover:scale-[1.01]">
                    <div class="flex flex-col sm:flex-row justify-between items-center">
                        <div>
                            <h1 class="text-4xl font-bold">{{ weather.city }}, {{ weather.country }}</h1>
                            <p class="text-xl mt-1">{{ weather.description }}</p>
                            <div class="mt-4 text-6xl font-extrabold">{{ weather.temp }}{{ temp_unit }}</div>
                            <p class="text-lg">Feels like {{ weather.feels_like }}{{ temp_unit }}</p>
                            <div class="flex gap-4 mt-3 text-sm">
                                <span>💧 Humidity: {{ weather.humidity }}%</span>
                                <span>💨 Wind: {{ weather.wind_speed }} {{ wind_unit }}</span>
                            </div>
                        </div>
                        <div class="mt-4 sm:mt-0">
                            <img src="https://openweathermap.org/img/wn/{{ weather.icon }}@4x.png" alt="weather icon" class="w-32 h-32">
                        </div>
                    </div>
                </div>

                <!-- Hourly Forecast -->
                {% if hourly %}
                <div class="bg-white/10 backdrop-blur-md rounded-2xl p-5 shadow-xl">
                    <h2 class="text-2xl font-semibold mb-3">⏱️ Next 12 Hours</h2>
                    <div class="flex overflow-x-auto gap-4 pb-2">
                        {% for h in hourly %}
                        <div class="hourly-card bg-white/20 rounded-xl p-3 text-center min-w-[80px]">
                            <p class="font-bold">{{ h.time }}</p>
                            <img src="https://openweathermap.org/img/wn/{{ h.icon }}.png" class="w-10 h-10 mx-auto">
                            <p>{{ h.temp }}{{ temp_unit }}</p>
                        </div>
                        {% endfor %}
                    </div>
                </div>
                {% endif %}

                <!-- 5-Day Chart -->
                <div class="bg-white/10 backdrop-blur-md rounded-2xl p-5 shadow-xl">
                    <h2 class="text-2xl font-semibold mb-3">📈 5-Day Temperature Trend</h2>
                    <canvas id="tempChart" width="400" height="200" class="w-full h-auto"></canvas>
                </div>
                {% else %}
                <div class="bg-red-500/70 rounded-2xl p-5 text-center">City not found. Try Harare, Bulawayo, Mutare...</div>
                {% endif %}
            </main>
        </div>
    </div>
    <script>
        const dates = {{ forecast_dates | tojson }};
        const temps = {{ forecast_temps | tojson }};
        const ctx = document.getElementById('tempChart').getContext('2d');
        const gradient = ctx.createLinearGradient(0, 0, 0, 400);
        gradient.addColorStop(0, 'rgba(52, 211, 153, 0.7)');
        gradient.addColorStop(1, 'rgba(52, 211, 153, 0.1)');
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: dates,
                datasets: [{
                    label: 'Temperature ({{ temp_unit }})',
                    data: temps,
                    borderColor: '#34d399',
                    backgroundColor: gradient,
                    borderWidth: 3,
                    pointBackgroundColor: '#fbbf24',
                    pointBorderColor: '#ffffff',
                    pointRadius: 5,
                    pointHoverRadius: 7,
                    tension: 0.2,
                    fill: true
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    tooltip: { callbacks: { label: (ctx) => `${ctx.raw}{{ temp_unit }}` } },
                    legend: { labels: { color: '#ffffff' } }
                },
                scales: {
                    y: { grid: { color: '#ffffff30' }, title: { display: true, text: '{{ temp_unit }}', color: '#fff' } },
                    x: { grid: { color: '#ffffff30' }, ticks: { color: '#fff' } }
                }
            }
        });
    </script>
</body>
</html>
'@

# Ensure templates folder exists
New-Item -ItemType Directory -Path "templates" -Force | Out-Null
$newIndexHtml | Out-File -FilePath "templates\index.html" -Encoding utf8

Write-Host "✅ index.html updated with hourly forecast, recent searches, wind/humidity, unit toggle, and dynamic backgrounds" -ForegroundColor Green

Write-Host ""
Write-Host "🎉 All features added! Restart your app with: python app.py" -ForegroundColor Magenta
Write-Host "🌐 Then open http://127.0.0.1:5000" -ForegroundColor Cyan
Write-Host ""
Write-Host "✨ New features:" -ForegroundColor Yellow
Write-Host "   • Wind speed & humidity" -ForegroundColor White
Write-Host "   • Recent searches (top 5)" -ForegroundColor White
Write-Host "   • Background changes with weather (sunny/cloudy/rainy/etc.)" -ForegroundColor White
Write-Host "   • Hourly forecast (next 12 hours, 3-hour steps)" -ForegroundColor White
Write-Host "   • Unit toggle (°C / °F) – click button in top-right" -ForegroundColor White
Write-Host ""
Write-Host "If you want to revert, rename app_backup.py and templates/index_backup.html" -ForegroundColor Gray