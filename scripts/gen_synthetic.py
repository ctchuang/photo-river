"""Generate a synthetic 20-year / ~20k-photo metadata set in the same shape the
Apple Photos export script produces, so the page can be swapped to real data.

Output: data/sample/photos.json (run from the repository root)  {"meta": {...}, "t": [unix s], "lat": [...], "lng": [...]}
"""
import json, math, random, calendar, datetime as dt

random.seed(20060901)

START = dt.datetime(2006, 9, 1)
END = dt.datetime(2026, 10, 20)

# (from, to, name, lat, lng, regular spots near home)
HOMES = [
    (dt.datetime(2006, 9, 1), dt.datetime(2013, 8, 15), "Taipei", 25.033, 121.565, [
        ("office", 25.041, 121.566, 5), ("parents", 24.990, 121.520, 3),
        ("Yangmingshan", 25.170, 121.550, 1), ("Tamsui", 25.170, 121.440, 1),
        ("Yilan", 24.750, 121.750, 0.6), ("Jiufen", 25.110, 121.845, 0.5),
    ]),
    (dt.datetime(2013, 8, 15), dt.datetime(2019, 6, 30), "Mountain View", 37.386, -122.084, [
        ("office", 37.422, -122.084, 5), ("San Francisco", 37.780, -122.420, 2.5),
        ("Santa Cruz", 36.970, -122.030, 0.8), ("Napa", 38.300, -122.290, 0.5),
        ("Half Moon Bay", 37.460, -122.430, 0.6), ("Berkeley", 37.870, -122.270, 0.7),
    ]),
    (dt.datetime(2019, 6, 30), END, "Taipei", 25.052, 121.532, [
        ("office", 25.080, 121.565, 5), ("parents", 24.990, 121.520, 3),
        ("Yangmingshan", 25.170, 121.550, 1), ("Tamsui", 25.170, 121.440, 1),
        ("Yilan", 24.750, 121.750, 0.8), ("Keelung", 25.130, 121.740, 0.5),
    ]),
]

# name, lat, lng, weight from Asia home, weight from US home, intercontinental?
DEST = [
    ("Tokyo", 35.68, 139.76, 6, 2), ("Kyoto", 35.01, 135.77, 3, 0.5), ("Osaka", 34.69, 135.50, 2, 0.3),
    ("Seoul", 37.57, 126.98, 3, 0.5), ("Hong Kong", 22.32, 114.17, 3, 0.3), ("Bangkok", 13.76, 100.50, 2, 0.3),
    ("Singapore", 1.35, 103.82, 2, 0.4), ("Bali", -8.41, 115.19, 1.2, 0.3), ("Hanoi", 21.03, 105.85, 0.8, 0),
    ("Shanghai", 31.23, 121.47, 1.5, 0.3), ("Beijing", 39.90, 116.40, 1, 0.3), ("Okinawa", 26.33, 127.80, 1.2, 0),
    ("London", 51.51, -0.13, 1, 1.2), ("Paris", 48.86, 2.35, 1, 1.2), ("Rome", 41.90, 12.50, 0.6, 0.6),
    ("Barcelona", 41.39, 2.17, 0.5, 0.6), ("Amsterdam", 52.37, 4.90, 0.4, 0.6), ("Lisbon", 38.72, -9.14, 0.3, 0.5),
    ("Reykjavik", 64.15, -21.94, 0.2, 0.5), ("New York", 40.71, -74.01, 1, 2.5), ("Seattle", 47.61, -122.33, 0.3, 1.5),
    ("Los Angeles", 34.05, -118.24, 0.3, 2), ("Las Vegas", 36.17, -115.14, 0.2, 1.2), ("Chicago", 41.88, -87.63, 0.2, 0.8),
    ("Austin", 30.27, -97.74, 0.1, 0.7), ("Boston", 42.36, -71.06, 0.2, 0.8), ("Honolulu", 21.31, -157.86, 0.5, 1.2),
    ("Vancouver", 49.28, -123.12, 0.3, 1), ("Mexico City", 19.43, -99.13, 0.1, 0.6), ("Sydney", -33.87, 151.21, 0.6, 0.4),
    ("San Francisco", 37.78, -122.42, 1.5, 0), ("Taipei (family)", 25.04, 121.55, 0, 3),
    # domestic / drivable
    ("Hualien", 23.99, 121.60, 1.5, 0), ("Kenting", 21.95, 120.80, 1.2, 0), ("Tainan", 22.99, 120.21, 1, 0),
    ("Taichung", 24.15, 120.67, 1, 0), ("Penghu", 23.57, 119.58, 0.5, 0), ("Alishan", 23.51, 120.80, 0.6, 0),
    ("Yosemite", 37.75, -119.59, 0, 1.2), ("Lake Tahoe", 39.09, -120.03, 0, 1.5), ("Portland", 45.52, -122.68, 0, 0.6),
    ("San Diego", 32.72, -117.16, 0, 0.8), ("Big Sur", 36.27, -121.81, 0, 0.8),
]
PAIRS = {"Tokyo": ["Kyoto", "Osaka"], "Kyoto": ["Osaka", "Tokyo"], "Paris": ["Barcelona", "Amsterdam", "London"],
         "London": ["Paris", "Amsterdam"], "Rome": ["Barcelona"], "New York": ["Boston"], "Seattle": ["Vancouver"],
         "Bangkok": ["Singapore"], "Hong Kong": ["Shanghai"]}


def haversine(a, b, c, d):
    R = 6371.0
    p1, p2 = math.radians(a), math.radians(c)
    dp, dl = math.radians(c - a), math.radians(d - b)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def jitter(lat, lng, km):
    r = km * math.sqrt(random.random())
    th = random.random() * 2 * math.pi
    return lat + (r * math.cos(th)) / 111.0, lng + (r * math.sin(th)) / (111.0 * max(0.2, math.cos(math.radians(lat))))


def home_at(day):
    for h in HOMES:
        if h[0] <= day < h[1]:
            return h
    return HOMES[-1]


def sigmoid(x):
    return 1 / (1 + math.exp(-x))


def daily_rate(day):
    y = day.year + day.timetuple().tm_yday / 365.0
    base = 0.45 + 1.75 * sigmoid((y - 2012.5) / 2.2)       # phone cameras get good
    if day.weekday() >= 5:
        base *= 1.7
    if dt.datetime(2016, 4, 10) <= day:                       # a baby arrives
        base *= 1.45 if day < dt.datetime(2019, 1, 1) else 1.2
    if dt.datetime(2020, 3, 1) <= day < dt.datetime(2021, 7, 1):
        base *= 0.75                                          # lockdown-ish
    return base


def time_in_day(day, mode):
    if mode == "trip":
        h = random.triangular(8, 23, 14)
    elif day.weekday() >= 5:
        h = random.triangular(9, 23, 15)
    else:
        h = random.choice([random.triangular(11.5, 13.5, 12.5), random.triangular(17.5, 23, 20), random.uniform(7, 23)])
    if dt.datetime(2016, 4, 10) <= day < dt.datetime(2017, 6, 1) and random.random() < 0.2:
        h = random.choice([random.uniform(0, 7), random.uniform(22, 24)])  # newborn hours
    return day + dt.timedelta(hours=min(23.99, max(0, h)))


def plan_trips():
    trips = []
    for year in range(2006, 2027):
        if year < 2009:
            n = 2
        elif year < 2013:
            n = 3
        elif year < 2020:
            n = 4
        elif year == 2020:
            n = 1
        elif year == 2021:
            n = 1
        else:
            n = 4
        for _ in range(n):
            start = dt.datetime(year, 1, 1) + dt.timedelta(days=random.randint(0, 364))
            if start < START or start > END - dt.timedelta(days=14):
                continue
            if dt.datetime(2020, 3, 15) <= start < dt.datetime(2021, 9, 1) and random.random() < 0.7:
                continue
            h = home_at(start)
            asia = h[2] == "Taipei"
            weights = [d[3] if asia else d[4] for d in DEST]
            d = random.choices(DEST, weights=weights)[0]
            far = haversine(h[3], h[4], d[1], d[2]) > 2500
            days = random.randint(7, 13) if far else random.randint(3, 7)
            cities = [d]
            if d[0] in PAIRS and random.random() < 0.45:
                name = random.choice(PAIRS[d[0]])
                cities.append(next(x for x in DEST if x[0] == name))
            trips.append((start, days, cities))
    trips.sort(key=lambda x: x[0])
    # drop overlaps
    out, last_end = [], START
    for t in trips:
        if t[0] >= last_end + dt.timedelta(days=5):
            out.append(t)
            last_end = t[0] + dt.timedelta(days=t[1])
    return out


def main():
    trips = plan_trips()
    trip_days = {}
    for start, days, cities in trips:
        for i in range(days):
            day = (start + dt.timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
            # split days across cities
            city = cities[min(len(cities) - 1, int(i * len(cities) / days))]
            trip_days[day.date()] = (city, i == 0, i == days - 1, start, days)

    recs = []
    day = START
    while day < END:
        h = home_at(day)
        key = day.date()
        if key in trip_days:
            city, first, last, start, days = trip_days[key]
            n = max(1, int(random.gauss(17, 6)))
            for _ in range(n):
                la, lo = jitter(city[1], city[2], 6)
                when = time_in_day(day, "trip")
                if first:   # arrive in the afternoon
                    when = day + dt.timedelta(hours=random.uniform(14, 23.5))
                if last:    # leave by late afternoon
                    when = day + dt.timedelta(hours=random.uniform(7, 16))
                recs.append((when, la, lo))
            if first:   # a couple of airport / departure shots near home
                for _ in range(random.randint(1, 3)):
                    la, lo = jitter(h[3], h[4], 22)
                    recs.append((day + dt.timedelta(hours=random.uniform(6, 11)), la, lo))
            if last:
                for _ in range(random.randint(0, 2)):
                    la, lo = jitter(h[3], h[4], 22)
                    recs.append((day + dt.timedelta(hours=random.uniform(20.5, 23.9)), la, lo))
        else:
            lam = daily_rate(day)
            # bursty: some days many, many days none
            n = 0
            if random.random() < min(0.9, lam / 2.2):
                n = max(1, int(random.expovariate(1 / lam)))
            for _ in range(n):
                spots = h[5]
                if random.random() < 0.72:
                    la, lo = jitter(h[3], h[4], 3.5)
                else:
                    s = random.choices(spots, weights=[x[3] for x in spots])[0]
                    la, lo = jitter(s[1], s[2], 1.5)
                recs.append((time_in_day(day, "home"), la, lo))
        day += dt.timedelta(days=1)

    recs.sort(key=lambda r: r[0])

    def to_ts(naive):
        # naive wall-clock time in the home's zone -> absolute unix time (+8 Taipei, -8 California)
        off = 8 * 3600 if home_at(naive)[2] == "Taipei" else -8 * 3600
        return int(calendar.timegm(naive.timetuple())) - off

    out = {
        "meta": {
            "source": "synthetic",
            "note": "Fake 20-year life for prototyping. Replace with scripts/export_photos.py output in data/photos.json.",
            "generated": dt.date.today().isoformat(),
            "count": len(recs),
            "homes": [[h[0].date().isoformat(), h[1].date().isoformat(), h[2], h[3], h[4]] for h in HOMES],
            "trips": [[s.date().isoformat(), d, [c[0] for c in cs]] for s, d, cs in trips],
        },
        "t": [to_ts(r[0]) for r in recs],
        "lat": [round(r[1], 3) for r in recs],
        "lng": [round(r[2], 3) for r in recs],
    }
    with open("data/sample/photos.json", "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print("photos:", len(recs), "trips:", len(trips))


if __name__ == "__main__":
    main()
