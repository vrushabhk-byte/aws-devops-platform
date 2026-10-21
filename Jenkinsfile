pipeline {
    agent any

    environment {
        K8S_NAMESPACE       = 'production'
        IMAGE_NAME          = 'aws-devops-platform'
        IMAGE_TAG           = 'local'
        KUBECONFIG           = '/root/.kube/config'
        KIND_CLUSTER         = 'aws-devops-local'
        MONITORING_NAMESPACE = 'monitoring'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
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

                    echo "=== Pytest ==="
                    python3 -m pytest --version

                    echo "=== kubectl ==="
                    kubectl --kubeconfig="$KUBECONFIG" version --client

                    echo "=== Kind cluster ==="
                    kind get clusters

                    echo "=== Kubernetes nodes ==="
                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get nodes
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu

                    echo "=== Installing application dependencies ==="

                    python3 -m pip install \
                        --break-system-packages \
                        -r requirements.txt

                    echo "=== Installing development dependencies ==="

                    python3 -m pip install \
                        --break-system-packages \
                        -r requirements-dev.txt

                    echo "=== Running pytest ==="

                    python3 -m pytest -v
                '''
            }
        }

        stage('Source Security Scan') {
            steps {
                sh '''
                    set -eu

                    echo "=== Scanning source code with Trivy ==="

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

                    echo "=== Building Docker image ==="

                    docker build \
                        --pull=false \
                        -t "$IMAGE_NAME:$IMAGE_TAG" \
                        .
                '''
            }
        }

        stage('Container Security Scan') {
            steps {
                sh '''
                    set -eu

                    echo "=== Scanning Docker image with Trivy ==="

                    trivy image \
                        --scanners vuln \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        "$IMAGE_NAME:$IMAGE_TAG"
                '''
            }
        }

        stage('Load Image into Kind') {
            steps {
                sh '''
                    set -eu

                    echo "=== Loading image into Kind ==="

                    kind load docker-image \
                        "$IMAGE_NAME:$IMAGE_TAG" \
                        --name "$KIND_CLUSTER"
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    set -eu

                    echo "=== Applying Kubernetes manifests ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        apply -f k8s/

                    echo "=== Waiting for application rollout ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        rollout status deployment/flask-api \
                        --namespace "$K8S_NAMESPACE" \
                        --timeout=180s

                    echo "=== Application pods ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get pods \
                        --namespace "$K8S_NAMESPACE" \
                        -o wide

                    echo "=== Application service ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get service flask-api \
                        --namespace "$K8S_NAMESPACE"
                '''
            }
        }

        stage('Deploy Monitoring Configuration') {
            steps {
                sh '''
                    set -eu

                    echo "=== Checking monitoring namespace ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get namespace "$MONITORING_NAMESPACE"

                    echo "=== Checking ServiceMonitor CRD ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get crd servicemonitors.monitoring.coreos.com

                    echo "=== Checking PrometheusRule CRD ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get crd prometheusrules.monitoring.coreos.com

                    echo "=== Applying ServiceMonitor ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        apply -f monitoring/flask-servicemonitor.yaml

                    echo "=== Applying Prometheus alert rules ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        apply -f monitoring/alerts/flask-alerts.yaml
                '''
            }
        }

        stage('Verify Monitoring Configuration') {
            steps {
                sh '''
                    set -eu

                    echo "=== Verifying ServiceMonitor ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get servicemonitor flask-api \
                        --namespace "$MONITORING_NAMESPACE" \
                        -o yaml

                    echo "=== Verifying PrometheusRule ==="

                    # Must match metadata.name in flask-alerts.yaml.
                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get prometheusrule flask-application-alerts \
                        --namespace "$MONITORING_NAMESPACE" \
                        -o yaml

                    echo "=== Listing configured alert names ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get prometheusrule flask-application-alerts \
                        --namespace "$MONITORING_NAMESPACE" \
                        -o jsonpath='{range .spec.groups[*].rules[*]}{.alert}{"\\n"}{end}'
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    set -eu

                    echo "=== Testing Flask health endpoint ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        run flask-smoke-test \
                        --namespace "$K8S_NAMESPACE" \
                        --image=curlimages/curl:8.12.1 \
                        --restart=Never \
                        --rm \
                        -i \
                        --quiet \
                        --command -- \
                        curl --fail --silent --show-error \
                        --max-time 10 \
                        http://flask-api/health

                    echo "=== Application smoke test passed ==="
                '''
            }
        }
    }

    post {
        success {
            echo '''
                Pipeline completed successfully.

                Unit tests, security scans, Docker build,
                Kubernetes deployment, monitoring verification,
                and application smoke test passed.
            '''
        }

        failure {
            echo '''
                Pipeline failed.

                Check the first failed stage in the Jenkins
                console output and resolve the reported issue.
            '''
        }

        always {
            echo 'Jenkins pipeline execution finished.'
        }
    }
}
