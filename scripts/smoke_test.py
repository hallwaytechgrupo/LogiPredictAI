"""Verifica Node -> Python -> modelo real, com ambos os serviços em execução."""
import argparse
import json
import urllib.error
import urllib.request
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:3001")
    args = parser.parse_args()

    def request(path, payload=None):
        req = urllib.request.Request(args.url + path, data=json.dumps(payload).encode() if payload else None,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as response:
            assert response.status == 200
            return json.load(response)

    assert request("/health")["status"] == "ok"
    ready = request("/ready")
    metadata = request("/api/v1/model")
    assert metadata["version"] == ready["model_version"]
    payload = json.loads(Path("examples/prediction.json").read_text(encoding="utf-8"))
    prediction = request("/api/v1/predictions", payload)
    assert 0 <= prediction["delay_probability"] <= 1
    assert prediction["predicted_late"] == (prediction["delay_probability"] >= prediction["threshold"])
    assert prediction["model_version"] == metadata["version"]
    analytics = request("/api/v1/analytics/states")
    assert analytics["type"] == "historical_observed"
    assert len(analytics["states"]) > 0
    invalid = {**payload, "customer_state": "XX"}
    try:
        request("/api/v1/predictions", invalid)
        raise AssertionError("UF inválida foi aceita.")
    except urllib.error.HTTPError as error:
        assert error.code == 422
    print(json.dumps({"result": "PASS", "source": metadata["source"], "prediction": prediction}, indent=2))


if __name__ == "__main__":
    main()
