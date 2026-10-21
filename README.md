# Production-Style AWS DevOps Platform

A portfolio project demonstrating an end-to-end delivery workflow for a containerized Flask API on AWS:

**GitHub → Jenkins → Tests → Trivy scan → Docker build → Amazon ECR → Amazon EKS → Kubernetes Service → CloudWatch**

Infrastructure is provisioned with Terraform. The repository also includes Kubernetes manifests, automated tests, a Jenkins pipeline, and an optional GitHub Actions CI workflow.

> **Scope note:** This is a production-style learning project, not a turnkey production platform. Review security, availability, compliance, capacity, and cost requirements before adapting it for real workloads.

## Architecture

```text
Developer
   |
   v
GitHub repository
   |
   | webhook / push
   v
Jenkins agent (Python, Docker, AWS CLI, kubectl, Trivy)
   |-- 1. Install dependencies and run pytest
   |-- 2. Scan source and container image with Trivy
   |-- 3. Build Docker image tagged with Git commit
   |-- 4. Push image to Amazon ECR
   |-- 5. Update kubeconfig and deploy to Amazon EKS
   |-- 6. Wait for rollout and check application health
   v
Amazon EKS
   |-- Kubernetes Deployment (2 replicas)
   |-- Kubernetes Service (LoadBalancer)
   v
AWS load balancer --> Flask API pods

Terraform provisions:
- VPC across two Availability Zones
- Public and private subnets
- One NAT Gateway (to reduce cost versus one per AZ)
- Amazon EKS cluster and managed node group
- Amazon ECR repository with image scanning and lifecycle policy
- EKS control-plane logging
```

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
├── .dockerignore
├── .gitignore
├── Dockerfile
├── Jenkinsfile
├── requirements.txt
├── requirements-dev.txt
└── README.md
```

## AWS resources and technologies

- **Compute and containers:** Amazon EKS, EC2 managed node group, Docker
- **Registry:** Amazon ECR
- **Networking:** VPC, public/private subnets, route tables, Internet Gateway, NAT Gateway, security groups
- **Identity:** IAM roles and policies managed by the EKS Terraform module
- **Monitoring:** EKS control-plane logs in CloudWatch; Kubernetes/application metrics can be extended separately
- **Infrastructure as Code:** Terraform modules
- **CI/CD:** Jenkins, GitHub, optional GitHub Actions
- **Security:** non-root container, health probes, ECR image scanning, Trivy, no secrets committed to Git

## Prerequisites

Install/configure these before deploying:

1. An AWS account and an IAM identity allowed to create the resources in this project.
2. AWS CLI v2 configured locally (`aws configure` or an approved SSO/role workflow).
3. Terraform (1.5+).
4. `kubectl`.
5. Docker.
6. Git.
7. For the Jenkins pipeline: a Jenkins agent with Python 3.12, pip, Docker Engine access, AWS CLI v2, `kubectl`, and Trivy installed. The agent's AWS identity must have permission to push to ECR and access the EKS cluster.

Check the AWS identity and region:

```bash
aws sts get-caller-identity
aws configure get region
```

The examples use `ap-south-1` (Mumbai). Change the region if you prefer another region.

## 1. Clone and inspect the project

```bash
git clone https://github.com/<YOUR_GITHUB_USERNAME>/aws-devops-platform.git
cd aws-devops-platform
```

Create your own GitHub repository and replace the URL above with your repository URL.

## 2. Run the application and tests locally

Use Python 3.12 if available:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -v
python -m flask --app app.main run --host 0.0.0.0 --port 5000
```

In another terminal:

```bash
curl http://127.0.0.1:5000/health
curl http://127.0.0.1:5000/
```

Expected health response:

```json
{"status":"healthy"}
```

Stop the local server with `Ctrl+C`.

## 3. Build and run the Docker image locally

```bash
docker build -t aws-devops-platform:local .
docker run --rm -p 5000:5000 aws-devops-platform:local
```

Then check `http://127.0.0.1:5000/health`. Stop the container with `Ctrl+C`.

## 4. Provision AWS infrastructure with Terraform

> **Important security step:** Before applying, set the EKS API endpoint allowlist to your current public IP. Do not leave the cluster API open to the internet.

Get your public IP from a trusted IP-checking service or your network administrator, then create a Terraform variables file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set `cluster_endpoint_public_access_cidrs` to your public IP in CIDR form, for example:

```hcl
cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
```

`203.0.113.10` is an example documentation IP. Replace it with your real public IP. If your IP changes, update this allowlist before running Terraform again.

Review the selected AWS region, EKS version, and node size in `terraform.tfvars` before proceeding.

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Keep `terraform.tfvars`, `tfplan`, state files, and any credentials out of Git. The included `.gitignore` excludes common Terraform local files.

Terraform creates billable AWS resources. Review the plan before approving it.

Get the outputs:

```bash
terraform output
```

Save the ECR repository URL and EKS cluster name for the Jenkins configuration. Return to the repository root when done:

```bash
cd ..
```

## 5. Configure kubectl

Run from the repository root (change region/name if you changed the defaults):

```bash
aws eks update-kubeconfig --region ap-south-1 --name aws-devops-platform
kubectl get nodes
kubectl get namespaces
```

If access is denied, check that the AWS identity used by `kubectl` is the identity that created the cluster or has been granted EKS access. Do not work around access problems by granting broad administrator permissions to every identity.

## 6. Configure Jenkins

### Required Jenkins agent tools

The agent that runs this pipeline needs:

- Git
- Python 3.12 and pip
- Docker CLI and access to a Docker daemon
- AWS CLI v2
- `kubectl`
- Trivy

Ensure the agent's AWS identity has:
- ECR authentication and push permissions for the project's repository
- permission to call `eks:DescribeCluster`
- Kubernetes authorization to deploy to the target namespace

Prefer an attached IAM role / temporary credentials (for example, an EC2 instance profile) over long-lived AWS access keys. If your Jenkins runs outside AWS, use your organization's approved OIDC/role-assumption approach. Do not commit credentials to this repository.

### Create the Jenkins job

1. Push this repository to GitHub.
2. In Jenkins, create a **Pipeline** job.
3. Configure the GitHub repository URL and branch (`main`).
4. Select **Pipeline script from SCM**, SCM **Git**, and script path `Jenkinsfile`.
5. Configure a GitHub webhook to trigger the job, or use a suitable SCM polling strategy.
6. Ensure the Jenkins agent can reach the EKS API endpoint from its network. Add its egress IP to `cluster_endpoint_public_access_cidrs` if appropriate.
7. Review the environment variables at the top of `Jenkinsfile` and update the region, cluster name, ECR repository, and namespace if you changed the Terraform defaults.
8. Run the job.

The pipeline runs tests, performs a filesystem scan, builds the image, scans the image, pushes it to ECR, deploys it to EKS, waits for rollout, and checks the health endpoint.

**Security scanning behavior:** Trivy is configured to fail the pipeline on HIGH/CRITICAL findings. For a real team, tune exceptions through a documented security review rather than silently disabling the scanner.

## 7. Check the deployment

```bash
kubectl get deployments -n production
kubectl get pods -n production
kubectl get service -n production
kubectl rollout status deployment/flask-api -n production
```

Get the load balancer address:

```bash
./scripts/get-service-url.sh production flask-api
```

The AWS load balancer can take a few minutes to provision. Once an external hostname appears, test:

```bash
curl http://<LOAD_BALANCER_HOSTNAME>/
curl http://<LOAD_BALANCER_HOSTNAME>/health
```

Use HTTPS and a managed certificate/domain before exposing a real production service.

## 8. Optional GitHub Actions CI

`.github/workflows/ci.yml` runs unit tests and a source filesystem scan on pull requests and pushes. It does not deploy to AWS. The Jenkins pipeline is the deployment pipeline in this project.

## 9. Terraform remote state (recommended for team use)

The project uses local state by default so that the first deployment is easy to understand. For team use, create a dedicated, versioned, encrypted S3 bucket for Terraform state and enable native S3 state locking with `use_lockfile = true`.

1. Create the state bucket separately with a unique name, encryption, versioning, and public-access blocking.
2. Review `terraform/backend.tf.example`, copy it to `terraform/backend.tf`, and replace the example bucket/key/region with your own values.
3. Run `terraform init -migrate-state` from `terraform/` and carefully review the migration prompt.
4. Back up and protect state files; they can contain sensitive infrastructure data.

Do not put backend credentials in the backend configuration. Use the AWS CLI's normal role/SSO credential chain. Do not create a shared state bucket using the same state it is supposed to store.

## 10. Cost and cleanup

This project creates billable resources, including an EKS cluster, EC2 worker nodes, NAT Gateway, ECR storage, and a Kubernetes LoadBalancer service. Actual charges vary by region, runtime, traffic, and instance sizes. The NAT Gateway, EKS control plane, worker nodes, and load balancer can continue to incur charges even when no application traffic is flowing.

When finished, delete the Kubernetes Service first so AWS can release its load balancer, then destroy the Terraform infrastructure:

```bash
kubectl delete service flask-api -n production --ignore-not-found
kubectl delete namespace production --ignore-not-found
cd terraform
terraform destroy
```

Review the destroy plan and confirm before proceeding. If the Terraform state is lost or resources were created outside Terraform, some resources may require manual cleanup. Do not delete the Terraform state until you have confirmed the AWS resources are removed.

## Troubleshooting

### `kubectl` cannot connect to the cluster
- Confirm `aws sts get-caller-identity` returns the intended AWS identity.
- Confirm the cluster is active and the region/name are correct.
- Confirm your current public IP is included in the EKS endpoint allowlist.
- Confirm the identity has EKS access and Kubernetes RBAC permissions.

### Jenkins cannot reach EKS
- Check the Jenkins agent's outbound IP and network path.
- Add only the required agent IP/CIDR to the endpoint allowlist.
- Confirm the agent role can describe the cluster and is authorized to deploy.

### Image pull errors
- Check the image URL/tag in the Deployment.
- Confirm the worker-node role can pull from ECR.
- Inspect pod events with `kubectl describe pod -n production <pod-name>`.

### Deployment rollout fails
```bash
kubectl describe deployment flask-api -n production
kubectl get pods -n production
kubectl describe pod -n production <pod-name>
kubectl logs -n production deployment/flask-api
```

### LoadBalancer address is pending
```bash
kubectl describe service flask-api -n production
kubectl get events -n production --sort-by=.lastTimestamp
```
Allow several minutes for AWS to provision the load balancer and verify that the AWS load-balancing components and cluster networking are healthy.

## Suggested future enhancements

- AWS Load Balancer Controller with an Application Load Balancer and HTTPS
- External Secrets integration with AWS Secrets Manager
- Prometheus and Grafana or Amazon Managed Service for Prometheus
- Deployment strategies such as canary or blue/green
- Policy-as-code and Terraform security scanning
- Separate dev/staging/prod environments and protected deployment approvals
- EKS access through private endpoints/VPN and restricted network paths
- Automated backup and disaster-recovery testing

## License

This project is provided for educational and portfolio use. Add a license file if you want to grant explicit reuse permissions.
