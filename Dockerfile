FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

RUN useradd --system --uid 10001 --no-create-home appuser

WORKDIR /app
COPY --chown=appuser:appuser app/server.py ./server.py

USER 10001:10001
EXPOSE 8080

CMD ["python", "server.py"]
