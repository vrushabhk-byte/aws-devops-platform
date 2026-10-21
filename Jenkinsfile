pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        K8S_NAMESPACE       = 'production'
        IMAGE_NAME          = 'aws-devops-platform'
        IMAGE_TAG           = 'local'
        KUBECONFIG           = '/root/.kube/config'
        KIND_CLUSTER         = 'aws-devops-local'
        MONITORING_NAMESPACE = 'monitoring'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eu

                    echo "=== Current Git Commit ==="
                    git log -1 --oneline

                    echo "=== Project Files ==="
                    ls -la
                '''
            }
        }

        stage('Validate Toolchain') {
            steps {
                sh '''
                    set -eu

                    echo "=== Git ==="
                    git --version

                    echo "=== Docker ==="
                    docker --version

                    echo "=== Trivy ==="
                    trivy --version

                    echo "=== Terraform ==="
                    terraform version

                    echo "=== Python ==="
                    python3 --version

                    echo "=== pip ==="
                    python3 -m pip --version

                    echo "=== kubectl ==="
                    kubectl version --client

                    echo "=== Kind ==="
                    kind version

                    echo "=== Verify Kind Cluster ==="
                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get nodes
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu

                    echo "=== Install Python Dependencies ==="
                    python3 -m pip install \
                        --break-system-packages \
                        -r requirements-dev.txt

                    echo "=== Verify pytest ==="
                    python3 -m pytest --version

                    echo "=== Run Unit Tests ==="
                    python3 -m pytest -v
                '''
            }
        }

        stage('Source Security Scan') {
            steps {
                sh '''
                    set -eu

                    echo "=== Scan Source Code and Configuration ==="

                    trivy fs \
                        --scanners vuln,misconfig,secret \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --skip-dirs .git \
                        --skip-dirs .venv \
                        --skip-dirs .pytest_cache \
                        .
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -eu

                    echo "=== Build Application Image ==="

                    docker build \
                        --pull \
                        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
                        .

                    echo "=== Verify Built Image ==="

                    docker image inspect \
                        "${IMAGE_NAME}:${IMAGE_TAG}" \
                        --format='Image ID: {{.Id}}'
                '''
            }
        }

        stage('Container Security Scan') {
            steps {
                sh '''
                    set -eu

                    echo "=== Scan Docker Image ==="

                    trivy image \
                        --scanners vuln,misconfig,secret \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        "${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }

        stage('Load Image into Kind') {
            steps {
                sh '''
                    set -eu

                    echo "=== Load Docker Image into Kind ==="

                    kind load docker-image \
                        "${IMAGE_NAME}:${IMAGE_TAG}" \
                        --name "${KIND_CLUSTER}"

                    echo "=== Verify Kind Cluster ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get nodes
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    set -eu

                    echo "=== Create Application Namespace ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        create namespace "${K8S_NAMESPACE}" \
                        --dry-run=client \
                        -o yaml | kubectl apply -f -

                    echo "=== Apply Kubernetes Manifests ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        apply -n "${K8S_NAMESPACE}" -f k8s/

                    echo "=== Update Deployment Image ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        set image deployment/flask-api \
                        flask-api="${IMAGE_NAME}:${IMAGE_TAG}" \
                        -n "${K8S_NAMESPACE}"

                    echo "=== Wait for Deployment Rollout ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        rollout status deployment/flask-api \
                        -n "${K8S_NAMESPACE}" \
                        --timeout=180s

                    echo "=== Application Resources ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get deployments,pods,services \
                        -n "${K8S_NAMESPACE}"
                '''
            }
        }

        stage('Deploy Monitoring Configuration') {
            steps {
                sh '''
                    set -eu

                    echo "=== Verify Monitoring Namespace ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get namespace "${MONITORING_NAMESPACE}"

                    echo "=== Apply ServiceMonitor ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        apply -f monitoring/flask-servicemonitor.yaml

                    echo "=== Apply Prometheus Alert Rules ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        apply -f monitoring/alerts/flask-alerts.yaml
                '''
            }
        }

        stage('Verify Monitoring Configuration') {
            steps {
                sh '''
                    set -eu

                    echo "=== Verify ServiceMonitor ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get servicemonitor flask-api \
                        -n "${MONITORING_NAMESPACE}"

                    echo "=== Verify PrometheusRule ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get prometheusrule flask-application-alerts \
                        -n "${MONITORING_NAMESPACE}"

                    echo "=== Configured Alert Rules ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get prometheusrule flask-application-alerts \
                        -n "${MONITORING_NAMESPACE}" \
                        -o jsonpath='{range .spec.groups[*]}Group: {.name}{"\\n"}{range .rules[*]}  Alert: {.alert}{"\\n"}{end}{end}'
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    set -eu

                    echo "=== Verify Application Service ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        get service flask-api \
                        -n "${K8S_NAMESPACE}"

                    echo "=== Test Application Health Endpoint ==="

                    kubectl \
                        --kubeconfig="${KUBECONFIG}" \
                        --context="kind-${KIND_CLUSTER}" \
                        run "flask-api-smoke-${BUILD_NUMBER}" \
                        --namespace="${K8S_NAMESPACE}" \
                        --image=curlimages/curl:8.12.1 \
                        --restart=Never \
                        --rm \
                        -i \
                        --quiet \
                        --command -- \
                        curl \
                            --fail \
                            --silent \
                            --show-error \
                            --retry 10 \
                            --retry-connrefused \
                            --retry-delay 2 \
                            http://flask-api/health

                    echo ""
                    echo "=== Smoke Test Passed ==="
                '''
            }
        }
    }

    post {
        success {
            echo '''
            ==========================================
                       PIPELINE SUCCEEDED
            ==========================================
            Unit tests passed.
            Security scans passed.
            Docker image built and scanned.
            Application deployed to local Kind.
            Monitoring configuration verified.
            Application health check passed.
            ==========================================
            '''
        }

        failure {
            echo '''
            ==========================================
                       PIPELINE FAILED
            ==========================================
            Check the first failed stage in the Jenkins
            console output and resolve the reported issue.
            ==========================================
            '''
        }

        always {
            echo 'Jenkins pipeline execution finished.'
        }
    }
}
