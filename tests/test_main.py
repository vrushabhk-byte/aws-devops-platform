from app.main import create_app


def test_index_returns_service_name():
    client = create_app().test_client()
    response = client.get("/")
    assert response.status_code == 200
    assert response.json["service"] == "aws-devops-platform"


def test_health_endpoint():
    response = create_app().test_client().get("/health")
    assert response.status_code == 200
    assert response.json == {"status": "healthy"}


def test_readiness_endpoint():
    response = create_app().test_client().get("/ready")
    assert response.status_code == 200
    assert response.json == {"status": "ready"}
