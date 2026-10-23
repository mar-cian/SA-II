FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

# Kein tzdata noetig: dieses Muster rechnet in UTC und benutzt zoneinfo nicht.
# Die Service Clock braucht es, weil sie CLOCK_TZ aufloest.

WORKDIR /app
COPY app.py /app/app.py

# Nicht privilegierter Benutzer. Die Anwendung installiert nichts und schreibt
# nichts, deshalb genuegt eine reine Kennung ohne eigenes Home.
USER 10001:10001

EXPOSE 8000
CMD ["python", "app.py"]
