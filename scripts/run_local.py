"""Inicia API e serviço ML juntos. Ctrl+C encerra ambos; --smoke testa e encerra."""
import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, default=Path("models/olist"))
    parser.add_argument("--port", type=int, default=3001)
    parser.add_argument("--ml-port", type=int, default=8000)
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    model_dir = (root / args.model_dir).resolve()
    if not (model_dir / "model.joblib").exists():
        parser.error(f"Modelo ausente em {model_dir}. Execute o treinamento indicado no README.")
    node = shutil.which("node")
    if not node:
        parser.error("Node.js não encontrado. Instale Node 22 ou posterior.")
    if args.port == args.ml_port or any(p < 1 or p > 65535 for p in [args.port, args.ml_port]):
        parser.error("Use duas portas válidas e distintas.")
    for port in [args.port, args.ml_port]:
        with socket.socket() as probe:
            if probe.connect_ex(("127.0.0.1", port)) == 0:
                parser.error(f"Porta {port} ocupada. Escolha --port/--ml-port para evitar conflito.")
    logs = root / "reports/local"
    logs.mkdir(parents=True, exist_ok=True)
    processes = []
    flags = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
    with (logs / "ml.log").open("w", encoding="utf-8") as ml_log, (logs / "api.log").open("w", encoding="utf-8") as api_log:
        try:
            env = {**os.environ, "MODEL_DIR": str(model_dir), "PORT": str(args.port), "HOST": "127.0.0.1",
                   "ML_URL": f"http://127.0.0.1:{args.ml_port}", "PYTHONUNBUFFERED": "1"}
            processes.append(subprocess.Popen(
                [sys.executable, "-m", "uvicorn", "logipredict.service:app", "--host", "127.0.0.1",
                 "--port", str(args.ml_port)], cwd=root, env=env, stdout=ml_log, stderr=ml_log, **flags))
            processes.append(subprocess.Popen([node, str(root / "api/src/server.js")], cwd=root / "api",
                                               env=env, stdout=api_log, stderr=api_log, **flags))
            for attempt in range(60):
                if any(p.poll() is not None for p in processes):
                    raise RuntimeError(f"Um serviço encerrou. Consulte {logs}.")
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{args.port}/ready", timeout=2) as response:
                        health = json.load(response)
                    break
                except (urllib.error.URLError, TimeoutError):
                    time.sleep(0.5)
            else:
                raise RuntimeError(f"Serviços não ficaram disponíveis. Consulte {logs}.")
            print(f"API: http://127.0.0.1:{args.port} | OpenAPI ML: http://127.0.0.1:{args.ml_port}/docs", flush=True)
            print(f"Modelo: {health['model_version']} | Sintético: {health['synthetic']}", flush=True)
            if args.smoke:
                subprocess.run([sys.executable, str(root / "scripts/smoke_test.py"),
                                "--url", f"http://127.0.0.1:{args.port}"], cwd=root, check=True)
            else:
                print("Ctrl+C encerra os dois serviços.", flush=True)
                while all(p.poll() is None for p in processes):
                    time.sleep(1)
                raise RuntimeError(f"Um serviço encerrou. Consulte {logs}.")
        except KeyboardInterrupt:
            print("Encerrando serviços...")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
            for process in processes:
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
