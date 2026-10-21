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

                    echo "=== kubectl ==="
                    kubectl --kubeconfig="$KUBECONFIG" version --client

                    echo "=== Kind cluster ==="
                    kind get clusters

                    kubectl --kubeconfig="$KUBECONFIG" \
                        get nodes \
                        --context="kind-$KIND_CLUSTER"
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu

                    echo "=== Installing Python dependencies ==="
                    python3 -m pip install \
                        --break-system-packages \
                        -r requirements.txt

                    echo "=== Running unit tests ==="
                    python3 -m unittest discover -s tests -v
                '''
            }
        }

        stage('Source Security Scan') {
            steps {
                sh '''
                    set -eu

                    echo "=== Scanning repository with Trivy ==="

                    trivy fs \
                        --scanners vuln,misconfig,secret \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --skip-dirs .git \
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

                    echo "=== Loading Docker image into Kind ==="

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

                    echo "=== Waiting for deployment rollout ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        rollout status deployment/flask-api \
                        --namespace "$K8S_NAMESPACE" \
                        --timeout=180s

                    echo "=== Checking application pods ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get pods \
                        --namespace "$K8S_NAMESPACE" \
                        -o wide
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

                    echo "=== Checking monitoring CRDs ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get crd servicemonitors.monitoring.coreos.com

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

                    # The resource name must match metadata.name in
                    # monitoring/alerts/flask-alerts.yaml.
                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get prometheusrule flask-application-alerts \
                        --namespace "$MONITORING_NAMESPACE" \
                        -o yaml

                    echo "=== Checking configured alert names ==="

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

                    echo "=== Checking Kubernetes service ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                        --context="kind-$KIND_CLUSTER" \
                        get service flask-api \
                        --namespace "$K8S_NAMESPACE"

                    echo "=== Testing application health endpoint ==="

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

                    echo "=== Smoke test completed successfully ==="
                '''
            }
        }
    }

    post {
        success {
            echo '''
                Pipeline completed successfully.

                Application deployment, monitoring configuration,
                security scans, and smoke tests passed.
            '''
        }

        failure {
            echo '''
                Pipeline failed.

                Review the failed stage in the Jenkins console output.
                Fix the underlying issue before rerunning the pipeline.
            '''
        }

        always {
            echo 'Jenkins pipeline execution finished.'
        }
    }
}
