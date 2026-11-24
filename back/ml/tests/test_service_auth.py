from fastapi.testclient import TestClient
from logipredict.service import create_app


def test_remote_service_requires_its_internal_token(monkeypatch, tmp_path):
    monkeypatch.setenv("ML_SERVICE_TOKEN", "validation-internal-token")
    with TestClient(create_app(tmp_path)) as client:
        assert client.get("/health").status_code == 401
        assert client.get("/health", headers={"Authorization": "Bearer wrong"}).status_code == 401
        response = client.get("/health", headers={"Authorization": "Bearer validation-internal-token"})
        assert response.status_code == 503
        assert "Modelo ausente" in response.json()["detail"]


def test_local_service_keeps_its_original_access(monkeypatch, tmp_path):
    monkeypatch.delenv("ML_SERVICE_TOKEN", raising=False)
    with TestClient(create_app(tmp_path)) as client:
        assert client.get("/health").status_code == 503
