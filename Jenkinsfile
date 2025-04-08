pipeline {
    agent any

    stages {
        stage('Git Checkout') {
            steps {
                git branch: 'main', changelog: false, credentialsId: '0f8e4388-ff6d-470a-b970-d4545d194333', poll: false, url: 'https://github.com/vvitsivakumar/jktest.git'
            }
        }

        stage('Install PHP') {
            steps {
                sh '''
                    if ! command -v php >/dev/null 2>&1; then
                        echo "PHP not found, installing..."
                        sudo apt update
                        sudo apt install -y php
                    else
                        echo "PHP already installed: $(php -v)"
                    fi
                '''
            }
        }

        stage('Run PHP File') {
            steps {
                sh 'php index.php'
            }
        }
    }
}
