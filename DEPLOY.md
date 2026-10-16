# Deployment and Screenshot Guide

This guide is written for Windows PowerShell. Run commands from the repository root unless noted. The local path is suitable for screenshots without an AWS account; the AWS path creates billable resources.

## 1. Prerequisites

Install Python 3.11, Docker Desktop, kubectl, Helm 3, Terraform, AWS CLI (AWS path), and the security tools you plan to demonstrate. Enable Kubernetes in Docker Desktop for the local cluster path.

### Guided local run (Ubuntu WSL + Minikube)

From the repository root in Ubuntu WSL:

```bash
bash ./run-local.sh
```

The script creates a separate `.venv-devops` Python 3.11 environment, runs unit/SAST/SCA checks, builds the Docker image, starts Minikube if it is not running, loads the image into Minikube, deploys the development Helm release, verifies endpoints, and pauses for screenshot capture. Docker Desktop must be running with WSL integration enabled. It does not provision AWS resources. Press Enter at each prompt after taking the requested screenshot; Ctrl+C stops the script and its temporary port-forward.

Check the commands available on `PATH`:

```powershell
py -3.11 --version
docker version
kubectl version --client
helm version
terraform version
aws --version
```

## 2. Application and tests

From the project root:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r application\requirements.txt pytest
python -m pytest tests -v
```

Expected result: four tests pass. **Screenshot:** the passing test summary.

Run the app:

```powershell
python application\app.py
```

Visit `http://localhost:5000/`, `/health`, `/ready`, and `/metrics`. Stop the server with `Ctrl+C` before reusing port 5000. **Screenshots:** the home page and a successful `/health` response.

## 3. Docker

Build from the repository root (the root `.dockerignore` is used by this build):

```powershell
docker build -f docker\Dockerfile -t devops-app:1.0.0 .
docker run -d --name devops-app -p 5000:5000 devops-app:1.0.0
docker ps
docker logs devops-app
Invoke-RestMethod http://localhost:5000/health
docker inspect --format='{{json .State.Health}}' devops-app
```

The health check uses Python's standard library; the final image does not require `curl`. **Screenshot:** the running container and healthy response. Clean up:

```powershell
docker rm -f devops-app
```

## 4. Local Kubernetes and Helm

Confirm Docker Desktop Kubernetes is selected and ready:

```powershell
kubectl config current-context
kubectl get nodes
```

Build the image so the local cluster can use it. For kind or minikube, load the image into that cluster using its image-load command.

```powershell
docker build -f docker\Dockerfile -t devops-app:1.0.0 .
helm lint .\helm
helm template devops-app .\helm `
  --namespace devops-dev `
  --values .\helm\values-dev.yaml `
  --set image.repository=devops-app `
  --set image.tag=1.0.0 `
  --set image.pullPolicy=Never
```

Install the chart:

```powershell
helm upgrade --install devops-app .\helm `
  --namespace devops-dev `
  --create-namespace `
  --values .\helm\values-dev.yaml `
  --set image.repository=devops-app `
  --set image.tag=1.0.0 `
  --set image.pullPolicy=Never

helm status devops-app -n devops-dev
kubectl get deployments,pods,services,configmaps,secrets -n devops-dev
kubectl rollout status deployment/devops-app -n devops-dev
```

The dev profile intentionally disables Ingress and HPA. The app is stateless, so the deployment does not create an unused PersistentVolumeClaim. **Screenshots:** Helm status, running Pod, Service, and ConfigMap/Secret resources.

In a second PowerShell window, test the Service:

```powershell
kubectl port-forward svc/devops-app-service 8080:80 -n devops-dev
```

Then visit `http://localhost:8080/health`. **Screenshot:** the successful health response.

To remove the local release:

```powershell
helm uninstall devops-app -n devops-dev
```

### Optional raw manifests

The files under `kubernetes/` are standalone manifests using the local image tag. Apply them in dependency order:

```powershell
kubectl apply -f kubernetes\namespace.yaml
kubectl apply -f kubernetes\configmap.yaml
kubectl apply -f kubernetes\secret.yaml
kubectl apply -f kubernetes\rbac.yaml
kubectl apply -f kubernetes\deployment.yaml
kubectl apply -f kubernetes\service.yaml
```

Only apply `kubernetes\hpa.yaml` after installing metrics-server. Only apply `kubernetes\ingress.yaml` after installing/configuring the AWS Load Balancer Controller and replacing its example host with a DNS name you control. The sample Ingress does not provision a certificate or DNS record.

## 5. Terraform and AWS

Terraform uses local state by default; keep `terraform.tfstate` private and backed up. It provisions a VPC, NAT gateway, EKS cluster/node group, ECR repository, and a GitHub Actions OIDC role with scoped ECR permissions and cluster access. These resources incur AWS charges.

Before applying:

1. Configure AWS credentials using your normal AWS CLI profile or environment-based credential mechanism; never commit credentials.
2. Copy and edit the sample variables:

   ```powershell
   Copy-Item terraform\terraform.tfvars.example terraform\terraform.tfvars
   notepad terraform\terraform.tfvars
   ```

3. Set `github_repository` to your exact `owner/repository`. Replace the documentation-only `203.0.113.10/32` value in `cluster_endpoint_public_access_cidrs` with trusted static egress addresses. GitHub-hosted runner egress IPs change; use a self-hosted runner inside the VPC or a runner with stable egress IPs for the CI deploy job. Do not allow `0.0.0.0/0`.
4. Initialize, review the plan, then apply only after confirming the resources and estimated costs:

   ```powershell
   Set-Location terraform
   terraform init
   terraform validate
   terraform plan -out=tfplan
   terraform apply tfplan
   terraform output
   ```

Configure kubectl using the output command, or:

```powershell
aws eks update-kubeconfig --region us-east-1 --name devops-cluster
kubectl get nodes
```

**Screenshots:** reviewed Terraform plan, Terraform outputs, and ready EKS nodes. To avoid ongoing charges after the project, destroy the resources deliberately:

```powershell
terraform destroy
```

## 6. GitHub Actions CI/CD

Push the project to your GitHub repository's `main` branch. In repository **Settings → Secrets and variables → Actions**, add:

- Secret `GITHUB_ACTIONS_ROLE_ARN`: Terraform output `github_actions_role_arn`.
- Variable `AWS_REGION`: region used by Terraform (defaults to `us-east-1` if omitted).
- Variable `ECR_REPOSITORY`: ECR repository **name**, normally `devops-app`, not the full registry URI.

The GitHub owner/repository in Terraform must match this repository. The OIDC role trust is restricted to pushes from `main`; pull requests run tests and source/dependency/secret scans but do not access AWS.

Workflow order: tests → Bandit SAST, pip-audit SCA, and Gitleaks → build and push SHA-tagged image to ECR → Trivy CRITICAL/HIGH image scan → security gate → Helm deployment to EKS. The deployment installs metrics-server for HPA and leaves Ingress disabled because a controller, DNS name, and TLS setup must be configured separately.

Check the **Actions** tab and capture the successful run and uploaded scan reports. The EKS node role has ECR read access, so the workload does not need a long-lived ECR image-pull secret.

## 7. Local DevSecOps checks

Install tools as needed:

```powershell
python -m pip install bandit pip-audit
```

Run SAST and SCA:

```powershell
bandit -r application -c security\bandit.yaml -ll
pip-audit -r application\requirements.txt
```

Run Gitleaks and Trivy if installed:

```powershell
gitleaks git --config security\.gitleaks.toml
trivy image --config security\trivy.yaml devops-app:1.0.0
```

The security-gate script is Bash; from Git Bash at the project root:

```bash
./security/security-gate.sh pass pass pass pass
./security/security-gate.sh fail pass pass pass
```

The first command should pass; the second should block. The script requires all four explicit results and rejects invalid inputs. **Screenshots:** scan output and both gate outcomes. Do not include credentials in screenshots.

## 8. Monitoring

Install Prometheus, Grafana, Alertmanager, and the Prometheus Operator CRDs using the community stack:

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community\kube-prometheus-stack `
  --namespace monitoring --create-namespace
```

Once the Prometheus Operator CRDs are ready, apply the ServiceMonitor and PrometheusRule:

```powershell
kubectl apply -f monitoring\service-monitor.yaml
kubectl apply -f monitoring\alert-rules.yml
```

The ServiceMonitor is in `monitoring` and selects the application Service in `devops-prod`. For a local Helm installation in `devops-dev`, change `namespaceSelector.matchNames` in the ServiceMonitor and the namespace selectors in `monitoring\alert-rules.yml` and `monitoring\grafana-dashboard.json` to `devops-dev`.

Port-forward Grafana and Prometheus:

```powershell
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Get Grafana's generated admin password from the `prometheus-grafana` Secret; do not assume a default password. Import `monitoring\grafana-dashboard.json` through the Grafana UI. Visit Grafana at `http://localhost:3000` and Prometheus targets at `http://localhost:9090/targets`. **Screenshots:** app scrape target, dashboard, and alert rules.

`monitoring\prometheus.yml` is an example standalone Prometheus configuration, not a Kubernetes manifest; do not apply it with `kubectl apply`.

## 9. GitOps with Argo CD

Install Argo CD in the cluster:

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
```

Edit `gitops\argocd-application.yaml`: set the repository URL and ECR image URI/tag for your deployment. The repository must be readable by Argo CD; private-repository credentials must be configured in Argo CD. The cluster must be able to pull from ECR through the node role. Apply and inspect:

```powershell
kubectl apply -f gitops\argocd-application.yaml
kubectl get applications.argoproj.io -n argocd
```

The manifest enables automated sync, pruning, and self-healing. Do not let Argo CD and the direct Helm deploy job manage the same release simultaneously: Argo CD may revert an image tag deployed by CI. In GitOps mode, make Git the source of the image tag and use Argo CD as the sole deployer. **Screenshot:** Argo CD reporting the app as Synced and Healthy.

The Kustomize alternative in `gitops\kustomization.yaml` is also available. Replace its example ECR account ID/tag and run `kubectl apply -k gitops`.

## 10. Troubleshooting challenge

The checked-in manifests are valid starting configurations; the failure scenarios in `TROUBLESHOOTING.md` are exercises to inject one at a time, not currently active defects. For a safe local exercise, deliberately set a bad liveness path, inspect the Pod events/logs, then restore `/health`:

```powershell
helm upgrade devops-app .\helm -n devops-dev `
  --values .\helm\values-dev.yaml `
  --set image.repository=devops-app `
  --set image.tag=1.0.0 `
  --set image.pullPolicy=Never `
  --set livenessProbe.httpGet.path=/wrong-health-path

kubectl get pods -n devops-dev
kubectl describe pod <pod-name> -n devops-dev
kubectl get events -n devops-dev --sort-by=.metadata.creationTimestamp
```

Restore and verify:

```powershell
helm upgrade devops-app .\helm -n devops-dev `
  --values .\helm\values-dev.yaml `
  --set image.repository=devops-app `
  --set image.tag=1.0.0 `
  --set image.pullPolicy=Never `
  --set livenessProbe.httpGet.path=/health
kubectl rollout status deployment/devops-app -n devops-dev
```

Document symptom, investigation, root cause, fix, and verification in `TROUBLESHOOTING.md`. **Screenshots:** failed probe/events and recovered Pod.

## Screenshot checklist

Capture the tests, app home/health, Docker container, Helm release, Kubernetes resources, GitHub Actions run, security reports, Terraform plan/output (AWS path), Prometheus target/Grafana dashboard, Argo CD status, and troubleshooting before/after. Store images under `screenshots\` and link them from the README. Redact tokens, account-sensitive information, and credentials.
