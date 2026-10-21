# Local DevOps Platform with AWS Infrastructure Design

⚠️ COPYRIGHT NOTICE — ALL RIGHTS RESERVED

Copyright © 2026 Vrushabh Kothari. All rights reserved.

This repository is published for portfolio and demonstration purposes only. No permission is granted to copy, reproduce, modify, distribute, sublicense, or commercially use the original source code without prior written permission from the copyright holder, except where permitted by applicable law.

Viewing or accessing this public repository does not grant permission to reuse its source code. Third-party components, dependencies, and other materials remain subject to their respective licenses.

An end-to-end DevOps portfolio project that demonstrates how to test, scan, build, deploy, and monitor a containerized Flask API using Jenkins, Docker, Trivy, Kubernetes (Kind), Prometheus, and Grafana.

The repository also contains Terraform configuration for a proposed AWS VPC and Amazon EKS environment. The Terraform configuration has been formatted, initialized, and validated, but **the AWS infrastructure has not been deployed**. The working CI/CD demonstration currently runs locally on Ubuntu.

## Project status

| Capability | Status |
|---|---|
| Flask API and automated tests | Implemented |
| Jenkins pipeline | Passing locally |
| Docker image build | Implemented |
| Trivy source scan | Passing |
| Trivy container vulnerability report | Generated and archived by Jenkins |
| Container security gate | Fails on fixable HIGH/CRITICAL findings; unresolved findings remain reported |
| Local Kubernetes deployment | Working on Kind |
| Prometheus ServiceMonitor and alert rules | Applied and verified |
| Application health check | Passing |
| Terraform AWS configuration | Formatted and validated; not applied to AWS |
| Amazon ECR / EKS deployment | Planned AWS path; not currently demonstrated |

> **Security transparency:** the current base image scan reported unresolved HIGH-severity operating-system vulnerabilities. The pipeline preserves and archives the full report, while the gate fails on HIGH/CRITICAL vulnerabilities for which Trivy reports an available fix. This policy does not mean the image is vulnerability-free. Review the archived report and update the base image/packages when fixes become available.

## Architecture

### Working local CI/CD flow

```text
Developer
   |
   v
GitHub repository
   |
   v
Jenkins Pipeline
   |
   +--> Checkout source
   +--> Validate toolchain
   +--> Run pytest
   +--> Trivy source scan
   +--> Build Docker image
   +--> Trivy container scan
   |       +--> JSON vulnerability report
   |       +--> Text vulnerability report
   |       +--> Security gate for fixable HIGH/CRITICAL findings
   |
   v
Load image into local Kind cluster
   |
   v
Kubernetes namespace: production
   |
   +--> Deployment: flask-api (2 replicas)
   +--> Service: flask-api
   +--> /health smoke test
   |
   v
Prometheus + Grafana monitoring stack
   |
   +--> ServiceMonitor
   +--> PrometheusRule with application alerts
```

### Intended AWS infrastructure design (not deployed)

The `terraform/` directory describes an AWS architecture intended for a future deployment, including a VPC, subnets across Availability Zones, Amazon EKS, a managed node group, ECR, security groups, and VPC endpoints. The current Terraform configuration has passed `terraform fmt -check`, `terraform init -backend=false`, and `terraform validate`.

Terraform validation checks configuration syntax and consistency; it does not prove that the infrastructure has been created, that all AWS permissions are correct, or that the deployment will work in an AWS account. No AWS deployment is claimed by this project.

## Technology stack

- **Application:** Python 3.12, Flask
- **Testing:** pytest
- **CI/CD:** Jenkins Pipeline, Git, GitHub
- **Containers:** Docker
- **Container security:** Trivy
- **Local Kubernetes:** Kind, kubectl
- **Monitoring:** Prometheus, Grafana, ServiceMonitor, PrometheusRule
- **Infrastructure as Code:** Terraform
- **Cloud design target:** AWS VPC, Amazon EKS, Amazon ECR, IAM, CloudWatch

## Repository layout

```text
aws-devops-platform/
├── app/
│   ├── __init__.py
│   └── main.py
├── tests/
│   └── test_main.py
├── k8s/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   └── service.yaml
├── monitoring/
│   ├── alerts/
│   │   └── flask-alerts.yaml
│   ├── flask-servicemonitor.yaml
│   └── values.yaml
├── jenkins/
│   ├── config/
│   │   └── kubeconfig
│   ├── docker-compose.yml
│   └── Dockerfile
├── terraform/
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── backend.tf.example
├── scripts/
│   ├── check-prerequisites.sh
│   └── get-service-url.sh
├── .github/workflows/ci.yml
├── Dockerfile
├── Jenkinsfile
├── requirements.txt
├── requirements-dev.txt
├── pytest.ini
├── CONTRIBUTING.md
└── README.md
```

## Prerequisites

For the local demonstration, install or configure:

- Git
- Python 3.12 and `venv`
- Docker Engine and Docker Compose
- Jenkins
- Kind and kubectl
- Terraform (for validating the AWS configuration)
- Trivy

The Jenkins container and local Kind cluster must be able to communicate through the configured Docker network. Review `jenkins/docker-compose.yml`, `jenkins/Dockerfile`, and `Jenkinsfile` if your environment differs.

## Run the Flask application and tests locally

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -v
```

Start the API:

```bash
python -m flask --app app.main run --host 0.0.0.0 --port 5000
```

In another terminal, check the health endpoint:

```bash
curl http://127.0.0.1:5000/health
```

Expected response:

```json
{"status":"healthy"}
```

Stop the server with `Ctrl+C`.

## Build and run the Docker image locally

Build the image:

```bash
docker build -t aws-devops-platform:local .
```

Run it:

```bash
docker run --rm -p 5000:5000 aws-devops-platform:local
```

Then test:

```bash
curl http://127.0.0.1:5000/health
```

Stop the container with `Ctrl+C`.

## Run the local Kubernetes demonstration

The local Kind cluster used for this project is named `aws-devops-local`. Confirm that it is available:

```bash
kind get clusters
kubectl config current-context
kubectl get nodes
```

The expected context is `kind-aws-devops-local`.

Inspect the application deployment and service:

```bash
kubectl get deployments -n production
kubectl get pods -n production
kubectl get services -n production
kubectl rollout status deployment/flask-api -n production
```

The current pipeline loads the locally built image into Kind, deploys the `flask-api` workload with two replicas, and checks the application health endpoint.

To inspect application logs:

```bash
kubectl logs -n production deployment/flask-api
```

To inspect events if a rollout fails:

```bash
kubectl get events -n production --sort-by=.lastTimestamp
kubectl describe deployment flask-api -n production
kubectl get pods -n production
```

## Jenkins pipeline

The Jenkins job is named `aws-devops-platform`. The local Jenkins UI is available at `http://localhost:8081` when the configured Compose stack is running.

The pipeline includes these stages:

1. **Checkout** — retrieves the repository revision.
2. **Validate Toolchain** — checks required tools and local cluster access.
3. **Unit Tests** — runs the automated pytest suite.
4. **Source Security Scan** — scans repository source and configuration with Trivy.
5. **Build Docker Image** — builds the Flask API image.
6. **Container Security Scan** — generates vulnerability reports and runs the security gate.
7. **Load Image into Kind** — makes the built image available to the local cluster.
8. **Deploy to Kubernetes** — deploys the application to the `production` namespace.
9. **Deploy Monitoring Configuration** — applies the ServiceMonitor and alert rules.
10. **Verify Monitoring Configuration** — checks that monitoring resources exist.
11. **Smoke Test** — checks the application health endpoint.

Run the job from Jenkins and review the console output. A successful run demonstrates the local workflow only; it does not indicate that an AWS environment has been provisioned.

## Container vulnerability reporting

The pipeline archives these reports as Jenkins build artifacts:

- `security-reports/container-vulnerabilities.json`
- `security-reports/container-vulnerabilities.txt`

The reports include HIGH and CRITICAL findings. The security gate uses Trivy's `--ignore-unfixed` option, so it fails for HIGH/CRITICAL findings with fixes available according to the current vulnerability database. Unfixed findings can still appear in the full report.

For a responsible review:

1. Open the Jenkins build's archived artifacts.
2. Inspect the text report for a quick summary.
3. Use the JSON report for detailed finding data.
4. Reassess the base image and packages when Debian security updates become available.
5. Document any accepted risk and review exceptions rather than hiding findings.

A passing gate means no findings matched that particular gate policy; it is not a guarantee that the image has no vulnerabilities.

## Prometheus and Grafana

The project uses a Prometheus/Grafana stack installed in the local Kubernetes cluster. The pipeline applies and verifies:

- `monitoring/flask-servicemonitor.yaml`
- `monitoring/alerts/flask-alerts.yaml`

The alert rules include:

- `FlaskApplicationUnavailable`
- `FlaskHighHttp5xxErrorRate`
- `FlaskHighP95Latency`
- `FlaskContainerRestartingFrequently`

Check the resources:

```bash
kubectl get servicemonitor -n monitoring
kubectl get prometheusrule -n monitoring
kubectl get pods -n monitoring
```

The monitoring stack and application metrics are part of the local demonstration. Access Prometheus or Grafana using the service names and ports configured by your Helm release and `monitoring/values.yaml`.

## Terraform: AWS infrastructure design

The Terraform files describe the intended AWS environment. To perform a local configuration check without provisioning resources:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

These commands do not create AWS resources.

**Do not run `terraform apply` unless you intentionally want to deploy into an AWS account and have reviewed the plan, security configuration, and expected charges.** AWS resources such as EKS, worker nodes, NAT Gateway, ECR storage, and load balancers can incur charges.

Before a real deployment, review at least:

- AWS region, EKS version, and node sizing
- Cluster API endpoint access and administrative access paths
- IAM permissions and Kubernetes authorization
- Network routing, security groups, and VPC endpoints
- Terraform state storage, locking, backup, and access controls
- Logging, monitoring, secrets management, and cost estimates
- Cleanup procedures and resources created outside Terraform

The current configuration is validated but not applied to AWS. Any future AWS deployment should be tested and documented separately.

## Security and repository hygiene

- Do not commit AWS credentials, kubeconfig credentials, Terraform state, plans, or `terraform.tfvars`.
- Keep access to Jenkins and its Docker socket restricted; Docker socket access is highly privileged.
- Review `jenkins/config/kubeconfig` before publishing. Do not publish a kubeconfig containing real credentials or private environment details.
- Keep the local development virtual environment, caches, and generated reports out of Git unless intentionally publishing sanitized examples.
- Review Trivy reports even when the configured gate passes.

## Troubleshooting

### Jenkins cannot access Kind

```bash
docker ps
kind get clusters
kubectl config current-context
kubectl get nodes
docker network inspect kind
```

Confirm the Jenkins container is attached to the expected `kind` network and has the intended kubeconfig mounted.

### Application pods do not become ready

```bash
kubectl get pods -n production
kubectl describe deployment flask-api -n production
kubectl describe pod -n production <pod-name>
kubectl logs -n production deployment/flask-api
kubectl get events -n production --sort-by=.lastTimestamp
```

Check the image name, image availability in Kind, container port, probes, and application logs.

### Trivy reports vulnerabilities

Review both archived reports and distinguish fixed from unfixed findings. Do not interpret a passing `--ignore-unfixed` gate as a vulnerability-free image.

### Terraform validation fails

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

Review the error output and the relevant variable/module versions. Validation alone does not prove that the AWS deployment will succeed.

## Potential future improvements

- Deploy the Terraform architecture into a dedicated AWS sandbox after a cost and security review.
- Add a controlled ECR push and EKS deployment stage for AWS.
- Add an explicit vulnerability exception process with expiry and ownership.
- Add Terraform security scanning and policy-as-code.
- Add deployment approvals and separate environments.
- Configure HTTPS, managed certificates, and a suitable ingress/load-balancer controller.
- Integrate AWS Secrets Manager or an external secrets solution.
- Add backup and disaster-recovery tests.

