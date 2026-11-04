FROM python:3.12.3-slim

WORKDIR /app

COPY back/ml/requirements-docker.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY back/ml/logipredict ./logipredict

ENV MODEL_DIR=/app/models/olist
EXPOSE 8000

CMD ["uvicorn", "logipredict.service:app", "--host", "0.0.0.0", "--port", "8000"]
