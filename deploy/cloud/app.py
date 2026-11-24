"""API e inferência em serviços gerenciados independentes, sem máquina virtual."""
from pathlib import Path

import modal

ROOT = Path(__file__).resolve().parents[2]
app = modal.App("logipredict-cloud")
ignored = ["**/__pycache__/**", "**/*.pyc", "**/*.pyo"]

ml_image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("libgomp1")
    .pip_install_from_requirements(ROOT / "back/ml/requirements-docker.txt")
    .add_local_dir(ROOT / "back/ml/logipredict", "/app/back/ml/logipredict", copy=True, ignore=ignored)
    .add_local_dir(ROOT / "back/ml/models/olist", "/app/back/ml/models/olist", copy=True)
    .add_local_dir(ROOT / "back/ml/map_data", "/app/back/ml/map_data", copy=True)
    .env({"PYTHONPATH": "/app/back/ml", "MODEL_DIR": "/app/back/ml/models/olist",
          "OMP_NUM_THREADS": "1", "MKL_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1"})
)
for directory in ("codigo", "artefatos", "dados"):
    ml_image = ml_image.add_local_dir(
        ROOT / "ML/modelos_finais" / directory,
        f"/app/ML/modelos_finais/{directory}", copy=True, ignore=ignored,
    )

api_image = (
    modal.Image.from_registry("node:22-bookworm-slim", add_python="3.12")
    .workdir("/app/back")
    .add_local_file(ROOT / "back/package.json", "/app/back/package.json", copy=True)
    .add_local_file(ROOT / "back/package-lock.json", "/app/back/package-lock.json", copy=True)
    .run_commands("npm ci --omit=dev")
    .add_local_dir(ROOT / "back/src", "/app/back/src", copy=True)
    .add_local_file(ROOT / "back/data/hubs/hubs.json", "/app/back/data/hubs/hubs.json", copy=True)
    .add_local_file(ROOT / "back/data/pedidos_logipredict.csv", "/app/back/data/pedidos_logipredict.csv", copy=True)
    .env({"HOST": "0.0.0.0", "PORT": "3001", "DATA_STORE": "postgres",
          "HUBS_FILE": "/app/back/data/hubs/hubs.json", "ML_TIMEOUT_MS": "90000",
          "CORS_ORIGINS": "https://hallwaytechgrupo.github.io"})
)
for filename in ("olist_geolocation_dataset.csv", "olist_orders_dataset.csv", "olist_customers_dataset.csv"):
    api_image = api_image.add_local_file(ROOT / "back/data/raw" / filename,
                                          f"/app/back/data/raw/{filename}", copy=True)


@app.function(image=ml_image, secrets=[modal.Secret.from_name("logipredict-ml")],
              cpu=1, memory=2048, min_containers=0, max_containers=2,
              scaledown_window=60, timeout=180, serialized=True, include_source=False)
@modal.concurrent(max_inputs=4)
@modal.asgi_app()
def model_service():
    from logipredict.service import app as service
    return service


@app.function(image=api_image, secrets=[modal.Secret.from_name("logipredict-api")],
              cpu=0.25, memory=1024, min_containers=0, max_containers=2,
              scaledown_window=60, timeout=180, serialized=True, include_source=False)
@modal.concurrent(max_inputs=20)
@modal.web_server(3001, startup_timeout=60)
def api():
    import os
    import subprocess
    os.environ["ML_URL"] = model_service.get_web_url()
    subprocess.Popen(["node", "src/server.js"], cwd="/app/back")
