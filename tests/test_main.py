from app.main import create_app


def test_index_returns_service_name():
    client = create_app().test_client()

    response = client.get("/")

    assert response.status_code == 200
    assert response.json["service"] == "aws-devops-platform"
    assert response.json["message"] == "Hello from the AWS DevOps Platform!"


def test_health_endpoint():
    client = create_app().test_client()

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json == {"status": "healthy"}


def test_readiness_endpoint():
    client = create_app().test_client()

    response = client.get("/ready")

    assert response.status_code == 200
    assert response.json == {"status": "ready"}


def test_metrics_endpoint_returns_prometheus_metrics():
    client = create_app().test_client()

    # Generate a request so the application has request metrics.
    client.get("/health")

    response = client.get("/metrics")

    assert response.status_code == 200
    assert "flask_http_requests_total" in response.text
    assert "flask_http_request_duration_seconds" in response.text
    assert "text/plain" in response.content_type


def test_metrics_endpoint_does_not_count_itself():
    client = create_app().test_client()

    client.get("/metrics")

    response = client.get("/metrics")

    assert response.status_code == 200
    assert 'endpoint="metrics"' not in response.text


def test_request_metrics_include_http_status():
    client = create_app().test_client()

    response = client.get("/health")

    assert response.status_code == 200

    metrics_response = client.get("/metrics")
    metrics_text = metrics_response.text

    assert 'endpoint="health",method="GET",status="200"' in metrics_text

