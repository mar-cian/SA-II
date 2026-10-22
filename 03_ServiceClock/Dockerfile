FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

# Zeitzonendaten. python:3.12-slim bringt sie nicht zuverlaessig mit, und ohne
# sie kann zoneinfo CLOCK_TZ nicht aufloesen. Die Anwendung faellt dann auf UTC
# zurueck und meldet sich als degraded; mit tzdata stimmt die Anzeige.
RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY app.py /app/app.py

# Nicht privilegierter Benutzer. Keine Installation und kein Schreibzugriff
# noetig, deshalb genuegt eine reine Kennung ohne eigenes Home.
USER 10001:10001

EXPOSE 8000
CMD ["python", "app.py"]
