web: alembic upgrade head && python -m app.db_roles && exec uvicorn app.main:app --host 0.0.0.0 --port $PORT --proxy-headers --forwarded-allow-ips='*'
