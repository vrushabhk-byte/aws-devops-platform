pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        AWS_REGION       = 'ap-south-1'
        EKS_CLUSTER_NAME = 'aws-devops-platform'
        ECR_REPOSITORY   = 'aws-devops-platform'
        K8S_NAMESPACE    = 'production'
        IMAGE_NAME       = 'flask-api'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()
                }
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu
                    python3 --version
                    python3 -m venv .venv
                    . .venv/bin/activate
                    python -m pip install --upgrade pip
                    pip install -r requirements-dev.txt
                    pytest -v
                '''
            }
        }

        stage('Source Security Scan') {
            steps {
                sh '''
                    set -eu
                    trivy fs --no-progress --exit-code 1 --severity HIGH,CRITICAL \
                      --ignore-unfixed .
                '''
            }
        }

        stage('Build Image') {
            steps {
                sh '''
                    set -eu
                    docker build --pull \
                      --label org.opencontainers.image.revision="$IMAGE_TAG" \
                      -t "$IMAGE_NAME:$IMAGE_TAG" .
                '''
            }
        }

        stage('Container Security Scan') {
            steps {
                sh '''
                    set -eu
                    trivy image --no-progress --exit-code 1 --severity HIGH,CRITICAL \
                      --ignore-unfixed "$IMAGE_NAME:$IMAGE_TAG"
                '''
            }
        }

        stage('Push to Amazon ECR') {
            steps {
                sh '''
                    set -eu
                    AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
                    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    ECR_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}"

                    aws ecr get-login-password --region "$AWS_REGION" \
                      | docker login --username AWS --password-stdin "$ECR_REGISTRY"

                    docker tag "$IMAGE_NAME:$IMAGE_TAG" "$ECR_URI:$IMAGE_TAG"
                    docker push "$ECR_URI:$IMAGE_TAG"

                    echo "$ECR_URI:$IMAGE_TAG" > image-uri.txt
                '''
                archiveArtifacts artifacts: 'image-uri.txt', fingerprint: true
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    set -eu
                    AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
                    ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

                    aws eks update-kubeconfig \
                      --region "$AWS_REGION" \
                      --name "$EKS_CLUSTER_NAME"

                    kubectl apply -f k8s/namespace.yaml
                    kubectl apply -f k8s/service.yaml

                    sed "s|IMAGE_PLACEHOLDER|${ECR_URI}:${IMAGE_TAG}|g" \
                      k8s/deployment.yaml | kubectl apply -f -

                    kubectl rollout status deployment/flask-api \
                      --namespace "$K8S_NAMESPACE" --timeout=5m
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    set -eu
                    kubectl get pods -n "$K8S_NAMESPACE" -o wide
                    kubectl get service flask-api -n "$K8S_NAMESPACE"
                    kubectl run "smoke-test-${BUILD_NUMBER}" \
                      --namespace "$K8S_NAMESPACE" \
                      --image=curlimages/curl:8.12.1 \
                      --restart=Never \
                      --command -- sh -c \
                      'for i in $(seq 1 20); do curl -fsS http://flask-api/health && exit 0; sleep 3; done; exit 1'
                    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
                      "pod/smoke-test-${BUILD_NUMBER}" \
                      --namespace "$K8S_NAMESPACE" --timeout=90s
                    kubectl logs "smoke-test-${BUILD_NUMBER}" -n "$K8S_NAMESPACE"
                    kubectl delete pod "smoke-test-${BUILD_NUMBER}" \
                      --namespace "$K8S_NAMESPACE" --ignore-not-found=true
                '''
            }
        }
    }

    post {
        always {
            sh 'rm -rf .venv || true'
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            echo 'Build, scan, push, deployment, and smoke test completed successfully.'
        }
        failure {
            echo 'Pipeline failed. Review the stage logs before retrying or rolling back.'
        }
    }
}
