pipeline {
    agent any

    stages {
        stage('Git Checkout') {
            steps {
                git branch:'main', changelog: false, credentialsId: '0f8e4388-ff6d-470a-b970-d4545d194333', poll: false, url: 'https://github.com/vvitsivakumar/jktest.git'
            }
        }
    }
}
