
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        DOCKERHUB_USERNAME = 'pranav2329h'
        DOCKERHUB_REPO = 'auto-rollback-demo'
        EC2_HOST = '13.232.215.205'
        EC2_USER = 'ubuntu'
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/pranav2329h/jenkins-auto-rollback.git'
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    env.IMAGE_TAG = "build-${BUILD_NUMBER}"
                    env.IMAGE_NAME = "${DOCKERHUB_USERNAME}/${DOCKERHUB_REPO}:${IMAGE_TAG}"
                }

                sh '''
                    echo "Building Docker image: $IMAGE_NAME"

                    docker build \
                      -t "$IMAGE_NAME" \
                      -t "$DOCKERHUB_USERNAME/$DOCKERHUB_REPO:latest" \
                      .
                '''
            }
        }

        stage('Push Image to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_TOKEN'
                    )
                ]) {
                    sh '''
                        set +x

                        printf '%s' "$DOCKER_TOKEN" | \
                          docker login \
                            --username "$DOCKER_USER" \
                            --password-stdin

                        docker push "$IMAGE_NAME"

                        docker push \
                          "$DOCKERHUB_USERNAME/$DOCKERHUB_REPO:latest"

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'ec2-ssh-key',
                        keyFileVariable: 'SSH_KEY'
                    ),
                    file(
                        credentialsId: 'ec2-known-hosts',
                        variable: 'KNOWN_HOSTS'
                    )
                ]) {
                    sh '''
                        set +x

                        echo "Copying deployment script to EC2..."

                        scp \
                          -i "$SSH_KEY" \
                          -o BatchMode=yes \
                          -o StrictHostKeyChecking=yes \
                          -o UserKnownHostsFile="$KNOWN_HOSTS" \
                          deploy.sh \
                          "$EC2_USER@$EC2_HOST:/home/ubuntu/deploy.sh"

                        echo "Starting deployment..."

                        ssh \
                          -i "$SSH_KEY" \
                          -o BatchMode=yes \
                          -o StrictHostKeyChecking=yes \
                          -o UserKnownHostsFile="$KNOWN_HOSTS" \
                          "$EC2_USER@$EC2_HOST" \
                          "chmod +x /home/ubuntu/deploy.sh && /home/ubuntu/deploy.sh '$IMAGE_NAME'"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'CI/CD pipeline completed successfully. Deployment is healthy.'
        }

        failure {
            echo 'CI/CD pipeline failed. Check the stage logs and EC2 deployment logs.'
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}

