pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        K8S_NAMESPACE = 'production'
        IMAGE_NAME    = 'aws-devops-platform'
        IMAGE_TAG     = 'local'
        KUBECONFIG    = '/root/.kube/config'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eu
                    echo "Git revision:"
                    git rev-parse --short=7 HEAD
                    echo "Project workspace: $WORKSPACE"
                '''
            }
        }

        stage('Validate Toolchain') {
            steps {
                sh '''
                    set -eu

                    echo "=== Python ==="
                    python3 --version

                    echo "=== Docker ==="
                    docker version

                    echo "=== Kubernetes ==="
                    kubectl --kubeconfig="$KUBECONFIG" \
                      get nodes

                    echo "=== Trivy ==="
                    trivy --version
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu

                    python3 -m venv .venv
                    . .venv/bin/activate

                    python -m pip install \
                      --disable-pip-version-check \
                      -r requirements-dev.txt

                    python -m pytest -v
                '''
            }
        }

        stage('Source Security Scan') {
            steps {
                sh '''
                    set -eu

                    echo "=== Scanning project source and configuration ==="

                    trivy fs \
                      --no-progress \
                      --scanners vuln,misconfig,secret \
                      --tf-exclude-downloaded-modules \
                      --exit-code 1 \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --skip-dirs .git \
                      --skip-dirs .venv \
                      --skip-dirs .pytest_cache \
                      --skip-dirs terraform/.terraform \
                      .
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -eu

                    docker build \
                      --label "org.opencontainers.image.revision=$(git rev-parse HEAD)" \
                      --label "org.opencontainers.image.title=aws-devops-platform" \
                      -t "$IMAGE_NAME:$IMAGE_TAG" \
                      .
                '''

                sh '''
                    set -eu
                    docker image inspect "$IMAGE_NAME:$IMAGE_TAG"
                '''
            }
        }

        stage('Container Security Scan') {
            steps {
                sh '''
                    set -eu

                    trivy image \
                      --no-progress \
                      --exit-code 1 \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      "$IMAGE_NAME:$IMAGE_TAG"
                '''
            }
        }

        stage('Load Image into Kind') {
            steps {
                sh '''
                    set -eu

                    kind load docker-image "$IMAGE_NAME:$IMAGE_TAG" \
                      --name aws-devops-local
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    set -eu

                    kubectl --kubeconfig="$KUBECONFIG" \
                      apply -f k8s/namespace.yaml

                    kubectl --kubeconfig="$KUBECONFIG" \
                      apply -f k8s/deployment.yaml

                    kubectl --kubeconfig="$KUBECONFIG" \
                      apply -f k8s/service.yaml

                    kubectl --kubeconfig="$KUBECONFIG" \
                      rollout status deployment/flask-api \
                      --namespace "$K8S_NAMESPACE" \
                      --timeout=180s
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    set -eu

                    echo "=== Deployment ==="
                    kubectl --kubeconfig="$KUBECONFIG" \
                      get deployment flask-api \
                      -n "$K8S_NAMESPACE"

                    echo "=== Pods ==="
                    kubectl --kubeconfig="$KUBECONFIG" \
                      get pods -n "$K8S_NAMESPACE" -o wide

                    echo "=== Service ==="
                    kubectl --kubeconfig="$KUBECONFIG" \
                      get service flask-api -n "$K8S_NAMESPACE"

                    echo "=== Application endpoints ==="

                    kubectl --kubeconfig="$KUBECONFIG" \
                      run "smoke-test-${BUILD_NUMBER}" \
                      --namespace "$K8S_NAMESPACE" \
                      --image=curlimages/curl:8.12.1 \
                      --restart=Never \
                      --image-pull-policy=IfNotPresent \
                      --command -- sh -c '
                        set -eu

                        for i in $(seq 1 30); do
                          if curl -fsS http://flask-api/health; then
                            echo
                            break
                          fi
                          sleep 2
                        done

                        curl -fsS http://flask-api/ready
                        echo

                        curl -fsS http://flask-api/
                        echo
                      '

                    kubectl --kubeconfig="$KUBECONFIG" \
                      wait \
                      --for=jsonpath='{.status.phase}'=Succeeded \
                      "pod/smoke-test-${BUILD_NUMBER}" \
                      --namespace "$K8S_NAMESPACE" \
                      --timeout=120s

                    kubectl --kubeconfig="$KUBECONFIG" \
                      logs "smoke-test-${BUILD_NUMBER}" \
                      --namespace "$K8S_NAMESPACE"
                '''
            }

            post {
                always {
                    sh '''
                        kubectl --kubeconfig="$KUBECONFIG" \
                          delete pod "smoke-test-${BUILD_NUMBER}" \
                          --namespace "$K8S_NAMESPACE" \
                          --ignore-not-found=true \
                          --wait=false || true
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'rm -rf .venv || true'
        }

        success {
            echo 'SUCCESS: Tests, security scans, Docker build, Kubernetes deployment, and smoke tests completed.'
        }

        failure {
            echo 'FAILURE: Review the failed stage logs before retrying.'
        }
    }
}
