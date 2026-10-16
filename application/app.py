"""
DevOps Final Project - Flask Application

Endpoints:
    GET /           - Home page
    GET /health     - Liveness probe (returns 200 when app is alive)
    GET /ready      - Readiness probe (returns 200 when app can serve traffic)
    GET /metrics    - Simple text-based metrics for Prometheus
"""

import os
import time
from flask import Flask, render_template, jsonify

app = Flask(__name__)

# Application metadata
APP_NAME = os.getenv("APP_NAME", "devops-app")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")

# Simple in-memory counters for metrics demo
REQUEST_COUNT = 0
START_TIME = time.time()


@app.before_request
def count_request():
    global REQUEST_COUNT
    REQUEST_COUNT += 1


@app.route("/")
def index():
    return render_template(
        "index.html",
        app_name=APP_NAME,
        app_version=APP_VERSION,
        environment=ENVIRONMENT,
    )


@app.route("/health")
def health():
    """Liveness probe endpoint."""
    return jsonify(
        {
            "status": "healthy",
            "app": APP_NAME,
            "version": APP_VERSION,
            "environment": ENVIRONMENT,
        }
    ), 200


@app.route("/ready")
def ready():
    """Readiness probe endpoint."""
    return jsonify(
        {
            "status": "ready",
            "app": APP_NAME,
        }
    ), 200


@app.route("/metrics")
def metrics():
    """Simple plain-text metrics endpoint for Prometheus scraping."""
    uptime = time.time() - START_TIME
    lines = [
        f'# HELP app_info Application metadata',
        f'# TYPE app_info gauge',
        f'app_info{{app="{APP_NAME}",version="{APP_VERSION}",env="{ENVIRONMENT}"}} 1',
        f'',
        f'# HELP app_requests_total Total number of HTTP requests',
        f'# TYPE app_requests_total counter',
        f'app_requests_total {REQUEST_COUNT}',
        f'',
        f'# HELP app_uptime_seconds Application uptime in seconds',
        f'# TYPE app_uptime_seconds counter',
        f'app_uptime_seconds {uptime:.2f}',
    ]
    return "\n".join(lines) + "\n", 200, {"Content-Type": "text/plain; version=0.0.4"}


if __name__ == "__main__":
    app.run(host=os.getenv("HOST", "127.0.0.1"), port=int(os.getenv("PORT", 5000)), debug=False)
