"""Registra as credenciais somente no cofre de segredos do provedor."""
import json
import secrets
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = Path(__file__).with_name(".env")


def read_env(filename):
    if not filename.exists():
        return {}
    return dict(line.split("=", 1) for line in filename.read_text(encoding="utf-8-sig").splitlines()
                if line.strip() and not line.lstrip().startswith("#") and "=" in line)


values = read_env(PRIVATE)
if not values.get("DATABASE_URL"):
    raise SystemExit("Preencha DATABASE_URL em deploy/cloud/.env antes de publicar.")
if not values.get("ML_SERVICE_TOKEN"):
    values["ML_SERVICE_TOKEN"] = secrets.token_urlsafe(48)
    with PRIVATE.open("a", encoding="utf-8") as stream:
        stream.write(f"\nML_SERVICE_TOKEN={values['ML_SERVICE_TOKEN']}\n")
api_values = {key: values[key] for key in ("DATABASE_URL", "ML_SERVICE_TOKEN")}
if values.get("CORS_ORIGINS"):
    api_values["CORS_ORIGINS"] = values["CORS_ORIGINS"]
route_key = values.get("OPENROUTE_API_KEY") or read_env(ROOT / "back/.env").get("OPENROUTE_API_KEY")
if route_key:
    api_values["OPENROUTE_API_KEY"] = route_key
def update_secret(name, content):
    runtime = ROOT / "reports/local"
    runtime.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".json", dir=runtime, delete=False) as stream:
        json.dump(content, stream)
        temporary = Path(stream.name)
    try:
        subprocess.run([sys.executable, "-m", "modal", "secret", "create", name,
                        "--from-json", str(temporary), "--force"], check=True, capture_output=True)
    finally:
        temporary.unlink(missing_ok=True)


update_secret("logipredict-ml", {"ML_SERVICE_TOKEN": values["ML_SERVICE_TOKEN"]})
update_secret("logipredict-api", api_values)
print("Credenciais registradas. Nenhum segredo acompanha o site ou o APK.")
