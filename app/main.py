from flask import Flask, jsonify
import os


def create_app() -> Flask:
    app = Flask(__name__)
    app.config["APP_VERSION"] = os.getenv("APP_VERSION", "dev")

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
        # Extend this endpoint with dependency checks when the app gains dependencies.
        return jsonify(status="ready"), 200

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
