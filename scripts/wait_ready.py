"""Espera pela disponibilidade dos serviços para a verificação automatizada."""
import time
import urllib.error
import urllib.request

for attempt in range(30):
    try:
        with urllib.request.urlopen("http://127.0.0.1:3001/ready", timeout=2) as response:
            if response.status == 200:
                print("Serviços disponíveis.")
                break
    except (urllib.error.URLError, TimeoutError):
        time.sleep(1)
else:
    raise SystemExit("Serviços não ficaram disponíveis em 30 tentativas.")
