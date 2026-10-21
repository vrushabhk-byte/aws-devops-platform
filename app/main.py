import os
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)


REQUEST_COUNT = Counter(
    "flask_http_requests_total",
    "Total HTTP requests handled by the Flask application.",
    ["method", "endpoint", "status"],
)

REQUEST_LATENCY = Histogram(
    "flask_http_request_duration_seconds",
    "HTTP request duration in seconds.",
    ["method", "endpoint"],
)

REQUEST_ERRORS = Counter(
    "flask_http_errors_total",
    "Total HTTP 5xx responses.",
    ["method", "endpoint", "status"],
)


def create_app() -> Flask:
    app = Flask(__name__)
    app.config["APP_VERSION"] = os.getenv("APP_VERSION", "dev")

    @app.before_request
    def start_request_timer():
        g.request_start_time = time.perf_counter()

    @app.after_request
    def record_request_metrics(response):
        # Exclude the metrics endpoint to avoid monitoring noise.
        if request.endpoint != "metrics":
            endpoint = request.endpoint or "unknown"
            method = request.method
            status = str(response.status_code)

            REQUEST_COUNT.labels(
                method=method,
                endpoint=endpoint,
                status=status,
            ).inc()

            if response.status_code >= 500:
                REQUEST_ERRORS.labels(
                    method=method,
                    endpoint=endpoint,
                    status=status,
                ).inc()

            start_time = getattr(g, "request_start_time", None)
            if start_time is not None:
                REQUEST_LATENCY.labels(
                    method=method,
                    endpoint=endpoint,
                ).observe(time.perf_counter() - start_time)

        return response

    @app.get("/")
    def index():
        return jsonify(
            service="aws-devops-platform",
            message="Hello from the AWS DevOps Platform!",
            version=app.config["APP_VERSION"],
        )

    @app.get("/health")
    def health():
        return jsonify(status="healthy"), 200

    @app.get("/ready")
    def ready():
        # Extend this endpoint with dependency checks when dependencies
        # are introduced.
        return jsonify(status="ready"), 200

    @app.get("/metrics")
    def metrics():
        return Response(
            generate_latest(),
            content_type=CONTENT_TYPE_LATEST,
        )

    return app


app = create_app()


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=int(os.getenv("PORT", "5000")),
    )
