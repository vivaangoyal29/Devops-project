#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

IMAGE_NAME="devops-app:1.0.0"
NAMESPACE="devops-dev"
RELEASE="devops-app"
PORT_FORWARD_PID=""
PORT_FORWARD_LOG="${TMPDIR:-/tmp}/devops-app-port-forward.log"

cleanup() {
    if [[ -n "$PORT_FORWARD_PID" ]] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        kill "$PORT_FORWARD_PID" 2>/dev/null || true
        wait "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

fail() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

pause_for_screenshot() {
    printf '\n%s\n' "$1"
    read -r -p "Take the screenshot, then press Enter to continue (Ctrl+C to stop): "
}

command -v python3.11 >/dev/null 2>&1 || fail "Python 3.11 is required. Install python3.11 and python3.11-venv, then rerun this script."
command -v docker >/dev/null 2>&1 || fail "Docker CLI is missing. Enable Docker Desktop WSL integration and rerun."
command -v minikube >/dev/null 2>&1 || fail "Minikube is not installed in this WSL distribution."
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed in this WSL distribution."
command -v helm >/dev/null 2>&1 || fail "Helm is not installed in this WSL distribution."
command -v curl >/dev/null 2>&1 || fail "curl is required."

printf '\n=== 1/7: Python environment, tests, and source security scans ===\n'
if [[ ! -x .venv-devops/bin/python ]]; then
    python3.11 -m venv .venv-devops
fi
PYTHON="$ROOT_DIR/.venv-devops/bin/python"
"$PYTHON" -c 'import sys; print("Using", sys.version.split()[0]); assert sys.version_info[:2] == (3, 11), "The .venv-devops environment must use Python 3.11."'
"$PYTHON" -m pip install --upgrade pip
"$PYTHON" -m pip install -r application/requirements.txt pytest bandit pip-audit
"$PYTHON" -m pytest tests -v
"$PYTHON" -m bandit -r application -c security/bandit.yaml -ll
"$PYTHON" -m pip_audit -r application/requirements.txt

if command -v gitleaks >/dev/null 2>&1; then
    if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        gitleaks git --config security/.gitleaks.toml
    else
        gitleaks dir --config security/.gitleaks.toml .
    fi
else
    printf 'Gitleaks not installed; skipping optional local secret scan (GitHub Actions runs it).\n'
fi
pause_for_screenshot "Screenshot: passing unit tests and source security scan results."

printf '\n=== 2/7: Docker build ===\n'
docker info >/dev/null || fail "Docker Engine is not reachable. Start Docker Desktop and enable WSL integration."
docker build -f docker/Dockerfile -t "$IMAGE_NAME" .
docker image inspect "$IMAGE_NAME" >/dev/null
docker image ls devops-app
if command -v trivy >/dev/null 2>&1; then
    trivy image --config security/trivy.yaml "$IMAGE_NAME"
else
    printf 'Trivy not installed; skipping optional local image scan (GitHub Actions runs it after ECR push).\n'
fi
pause_for_screenshot "Screenshot: Docker image listed above. Docker Desktop must be running."

printf '\n=== 3/7: Minikube cluster ===\n'
if ! minikube status -p minikube >/dev/null 2>&1; then
    printf 'Minikube is not running; starting the minikube profile.\n'
    minikube start -p minikube
fi
minikube update-context -p minikube
kubectl config use-context minikube
kubectl wait --for=condition=Ready nodes --all --timeout=180s
kubectl get nodes -o wide
pause_for_screenshot "Screenshot: Minikube node in Ready state."

printf '\n=== 4/7: Load image into Minikube ===\n'
minikube image load "$IMAGE_NAME" -p minikube
minikube image ls -p minikube | grep -F 'devops-app' || fail "The devops-app image was not found in Minikube after loading."

printf '\n=== 5/7: Helm lint, render, and deploy ===\n'
helm lint ./helm
helm template "$RELEASE" ./helm \
    --namespace "$NAMESPACE" \
    --values ./helm/values-dev.yaml \
    --set image.repository=devops-app \
    --set image.tag=1.0.0 \
    --set image.pullPolicy=Never >/dev/null

helm upgrade --install "$RELEASE" ./helm \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --values ./helm/values-dev.yaml \
    --set image.repository=devops-app \
    --set image.tag=1.0.0 \
    --set image.pullPolicy=Never

kubectl rollout status "deployment/$RELEASE" -n "$NAMESPACE" --timeout=240s
helm status "$RELEASE" -n "$NAMESPACE"
kubectl get deployments,pods,services,configmaps,secrets -n "$NAMESPACE" -o wide
pause_for_screenshot "Screenshot: Helm release, Ready Pod, Service, ConfigMap, and Secret."

printf '\n=== 6/7: Forward the app Service for browser screenshots ===\n'
kubectl port-forward "service/${RELEASE}-service" 8080:80 -n "$NAMESPACE" >"$PORT_FORWARD_LOG" 2>&1 &
PORT_FORWARD_PID=$!

ready=0
for attempt in $(seq 1 30); do
    if ! kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
        cat "$PORT_FORWARD_LOG" >&2
        fail "kubectl port-forward exited. Check the output above."
    fi
    if curl --silent --show-error --fail http://127.0.0.1:8080/health >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
[[ "$ready" -eq 1 ]] || {
    cat "$PORT_FORWARD_LOG" >&2
    fail "The app health endpoint did not respond through port-forward."
}

printf 'Health response:\n'
curl --fail --show-error http://127.0.0.1:8080/health
printf '\nReadiness response:\n'
curl --fail --show-error http://127.0.0.1:8080/ready
printf '\nMetrics sample:\n'
curl --fail --show-error http://127.0.0.1:8080/metrics | head -n 8
printf '\nBrowser URLs while this script waits:\n'
printf '  Home:     http://localhost:8080/\n'
printf '  Health:   http://localhost:8080/health\n'
printf '  Ready:    http://localhost:8080/ready\n'
printf '  Metrics:  http://localhost:8080/metrics\n'
read -r -p "Capture the browser endpoint screenshots, then press Enter to close port-forward and finish: "

printf '\n=== 7/7: Final local verification ===\n'
kubectl get pods,services -n "$NAMESPACE"
printf '\nLocal deployment complete. No Terraform apply or AWS resources were created.\n'
printf 'Next: configure your GitHub repository and AWS values, then review terraform plan before any apply.\n'
