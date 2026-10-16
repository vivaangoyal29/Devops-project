import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "application"))

from app import app


def test_health_endpoint():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"


def test_ready_endpoint():
    client = app.test_client()
    response = client.get("/ready")
    assert response.status_code == 200


def test_home_endpoint():
    client = app.test_client()
    response = client.get("/")
    assert response.status_code == 200


def test_metrics_endpoint():
    client = app.test_client()
    response = client.get("/metrics")
    assert response.status_code == 200
    assert b"app_requests_total" in response.data
