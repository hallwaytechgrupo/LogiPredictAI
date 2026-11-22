FROM python:3.12.3-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY back/ml/requirements-docker.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY back/ml/logipredict ./logipredict
COPY back/ml/map_data ./map_data
COPY ML/modelos_finais /ML/modelos_finais

ENV MODEL_DIR=/app/models/olist
EXPOSE 8000

CMD ["uvicorn", "logipredict.service:app", "--host", "0.0.0.0", "--port", "8000"]
