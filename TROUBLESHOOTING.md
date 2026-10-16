# Final Troubleshooting Challenge

The repository contains working starting configurations. These are lab scenarios: deliberately introduce one failure at a time, gather evidence, identify the root cause, restore the configuration, and document the result. Do not leave broken values committed or deployed.

For a local lab, use the Helm release in namespace `devops-dev` from [DEPLOY.md](DEPLOY.md). Production examples use `devops-prod`. Replace `<pod-name>` with the actual pod name from `kubectl get pods`.

## Troubleshooting workflow

1. Record the symptom and recent change.
2. Inspect status, events, pod description, and logs.
3. State the root cause based on evidence, not guesswork.
4. Correct the manifest/value and redeploy.
5. Verify rollout and the endpoint.
6. Record commands, before/after evidence, and the final result below.

Useful commands:

```powershell
kubectl get pods -n devops-dev
kubectl describe pod <pod-name> -n devops-dev
kubectl logs <pod-name> -n devops-dev --previous
kubectl get events -n devops-dev --sort-by=.metadata.creationTimestamp
kubectl rollout status deployment/devops-app -n devops-dev
```

## Scenario 1: Image unavailable (`ErrImageNeverPull`)

**Inject:** Upgrade the Helm release with a nonexistent tag:

```powershell
helm upgrade devops-app .\helm -n devops-dev `
  --values .\helm\values-dev.yaml `
  --set image.repository=devops-app `
  --set image.tag=does-not-exist `
  --set image.pullPolicy=Never
```

**Investigate:** `kubectl describe pod <pod-name> -n devops-dev` and review the events. With `imagePullPolicy: Never`, the message should report that the local image is unavailable. With `imagePullPolicy: Always`, the same missing tag normally appears as `ImagePullBackOff`.

**Root cause:** The requested image/tag is not available in the local cluster. In EKS, also verify the ECR URI/region and the node role's ECR read permissions.

**Fix:** Restore tag `1.0.0` and make sure the image is built/loaded into the cluster.

**Verify:**

```powershell
helm upgrade devops-app .\helm -n devops-dev `
  --values .\helm\values-dev.yaml `
  --set image.repository=devops-app `
  --set image.tag=1.0.0 `
  --set image.pullPolicy=Never
kubectl rollout status deployment/devops-app -n devops-dev
```

## Scenario 2: Service sends traffic to the wrong port / Ingress 502

**Inject:** Change `service.targetPort` to `8080` in the chart values, or in `kubernetes/service.yaml`, while the container still listens on port `5000`.

**Investigate:**

```powershell
kubectl get endpoints devops-app-service -n devops-dev
kubectl describe service devops-app-service -n devops-dev
kubectl get pods -n devops-dev
```

**Root cause:** Service `targetPort` must map to the container's listening port (`5000`). The Endpoint may still list a Pod IP but with the incorrect port. A misrouted Service can result in connection failures/502s through a configured Ingress. The checked-in Service correctly targets port `5000`.

**Fix:** Restore `service.targetPort: 5000`.

**Verify:** Endpoints are populated and `kubectl port-forward svc/devops-app-service 8080:80 -n devops-dev` followed by `Invoke-RestMethod http://localhost:8080/health` succeeds. An actual Ingress test additionally requires the ingress controller, DNS, and TLS prerequisites.

## Scenario 3: ConfigMap reference does not match

**Inject:** Change the Deployment's `envFrom.configMapRef.name` to a nonexistent name.

**Investigate:** Describe the affected Pod and inspect namespace ConfigMaps:

```powershell
kubectl describe pod <pod-name> -n devops-dev
kubectl get configmaps -n devops-dev
```

**Root cause:** Kubernetes cannot construct the container environment from a missing, non-optional ConfigMap and reports a configuration error. The Flask app has defaults for some settings, so do not assume every missing value causes an application crash.

**Fix:** Restore the reference to the chart-generated ConfigMap or create the correctly named ConfigMap.

**Verify:** The Pod starts, `kubectl exec <pod-name> -n devops-dev -- printenv APP_NAME` shows the configured value, and the readiness endpoint returns 200.

## Scenario 4: EKS cannot pull the private ECR image

**Inject:** Use an incorrect AWS region, ECR account/repository URI, or remove ECR read access from the EKS node role in a test environment.

**Investigate:**

```powershell
kubectl describe pod <pod-name> -n devops-prod
aws ecr describe-images --region <region> --repository-name devops-app
```

**Root cause:** EKS worker nodes need permission to pull from ECR and the image URI/tag must exist in the same expected account/region. This project's node role includes `AmazonEC2ContainerRegistryReadOnly`; do not create a long-lived ECR password Secret. Local clusters should instead use a locally available image or a registry configured for that cluster.

**Fix:** Correct the image URI/tag/region or restore the node role's ECR read permissions, then redeploy.

**Verify:** The Pod events show a successful image pull and rollout completes.

## Scenario 5: HPA has unknown metrics or does not scale

**Inject:** In the Helm release, enable autoscaling without metrics-server or remove CPU/memory resource requests from a test deployment.

**Investigate:**

```powershell
kubectl get hpa -n devops-prod
kubectl describe hpa devops-app-hpa -n devops-prod
kubectl top pods -n devops-prod
```

**Root cause:** HPA requires metrics-server and relevant CPU/memory requests for utilization-based targets. The AWS GitHub Actions deployment installs metrics-server; local clusters need it installed separately.

**Fix:** Install a compatible metrics-server and restore requests in the Helm values/deployment.

**Verify:** `kubectl top pods` returns metrics and HPA `TARGETS` no longer shows `<unknown>`. Scaling requires workload above the configured utilization target.

## Scenario 6: Liveness probe fails

**Inject:** Change the liveness probe path to `/healthz`; the application exposes `/health`.

**Investigate:**

```powershell
kubectl describe pod <pod-name> -n devops-dev
kubectl logs <pod-name> -n devops-dev --previous
```

**Root cause:** The health endpoint path is incorrect. Kubernetes restarts the container after the liveness probe repeatedly fails. A readiness failure alone removes the Pod from Service endpoints but does not restart it.

**Fix:** Restore `livenessProbe.httpGet.path: /health`.

**Verify:** Wait for rollout, confirm the restart count stops increasing, and query `/health` via port-forward.

## Scenario 7: Secret resource reference is missing

**Inject:** Change `envFrom.secretRef.name` to a nonexistent Secret name in a test Deployment.

**Investigate:** Describe the Pod and list Secrets in its namespace:

```powershell
kubectl describe pod <pod-name> -n devops-dev
kubectl get secrets -n devops-dev
```

**Root cause:** The Pod references a Secret resource that does not exist. The current app does not use `DB_PASSWORD` or `API_TOKEN`, so changing either key alone does not cause a Flask `KeyError`.

**Fix:** Restore the Secret reference to the Helm-generated Secret or create the correctly named Secret. Do not put real credentials into repository files.

**Verify:** The Pod starts and the app health endpoint responds successfully.

## Lab record

| Field | Notes |
|---|---|
| Scenario and date | Scenario 6: Liveness probe fails (October 16, 2026) |
| Symptom and evidence | Pod restart count increased (`RESTARTS: 1`, `0/1 Running`). Events reported `Warning Unhealthy: Liveness probe failed: HTTP probe failed with statuscode: 404`, followed by `Normal Killing: Container devops-app failed liveness probe, will be restarted`. |
| Investigation commands | `kubectl get pods -n devops-dev`, `kubectl describe pod <pod-name> -n devops-dev`, `kubectl get events -n devops-dev --sort-by=.metadata.creationTimestamp` |
| Root cause | The liveness probe was configured with path `/wrong-health-path`, which returned HTTP 404 from the Flask application. After 3 consecutive failed checks (`failureThreshold: 3`), the kubelet restarted the container. |
| Fix applied | Upgraded Helm release in `devops-dev` with `livenessProbe.httpGet.path=/health`. |
| Verification result | Rollout succeeded (`deployment "devops-app" successfully rolled out`), new pod reached `1/1 Running` status with 0 restarts, and `/health` responded with 200 OK. |
| Screenshot path | `screenshots/09-troubleshooting.png` |
