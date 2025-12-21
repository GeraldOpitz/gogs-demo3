pipeline {
    agent any

    environment {
        TF_AWS_DIR = "${env.WORKSPACE}/terraform/environments/aws/dev"
        TF_GCP_DIR = "${env.WORKSPACE}/terraform/environments/gcp/dev"
    }

    stages {

        stage('Clean Workspace') {
            steps {
                deleteDir()
            }
        }

        stage('Clone Terraform Project') {
            steps {
                dir("${env.WORKSPACE}/terraform") {
                    sh '''
                        git clone -b GOGS-5-Terraform-GCP \
                        https://github.com/GeraldOpitz/gogs-tf .
                    '''
                }
            }
        }

        stage('Derive GCP SSH Public Key') {
            steps {
                withCredentials([
                    sshUserPrivateKey(
                        credentialsId: 'gcp-gogs-key',
                        keyFileVariable: 'SSH_KEY_FILE'
                    )
                ]) {
                    sh '''
                        echo "Deriving public key from Jenkins SSH private key"
                        PUB_KEY=$(ssh-keygen -y -f "$SSH_KEY_FILE")
                        export TF_VAR_jenkins_ssh_public_key="$PUB_KEY"
                        echo "Public key derived successfully"
                    '''
                }
            }
        }

        stage('Terraform Init') {
            parallel {

                stage('Init AWS') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_AWS_DIR}") {
                                withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                    sh 'terraform init -backend-config="backend.hcl"'
                                }
                            }
                        }
                    }
                }

                stage('Init GCP') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_GCP_DIR}") {
                                withCredentials([
                                    file(credentialsId: 'gcp-sa-key', variable: 'GCP_KEY')
                                ]) {
                                    sh '''
                                        export GOOGLE_APPLICATION_CREDENTIALS=$GCP_KEY
                                        terraform init
                                    '''
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Terraform Plan') {
            parallel {

                stage('Plan AWS') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_AWS_DIR}") {
                                withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                    sh 'terraform plan -out=tfplan'
                                }
                            }
                        }
                    }
                }

                stage('Plan GCP') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_GCP_DIR}") {
                                withCredentials([
                                    file(credentialsId: 'gcp-sa-key', variable: 'GCP_KEY')
                                ]) {
                                    sh '''
                                        export GOOGLE_APPLICATION_CREDENTIALS=$GCP_KEY
                                        terraform plan -out=tfplan
                                    '''
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Terraform Apply Approval') {
            when {
                allOf {
                    expression { !env.CHANGE_ID }
                    anyOf {
                        branch 'develop'
                        branch 'main'
                        branch 'feature/jenkinsfile'
                    }
                }
            }
            steps {
                input message: "¿Aplicar infraestructura en AWS y GCP?", ok: "Aplicar"
            }
        }

        stage('Terraform Apply') {
            when {
                allOf {
                    expression { !env.CHANGE_ID }
                    anyOf {
                        branch 'develop'
                        branch 'main'
                        branch 'feature/jenkinsfile'
                    }
                }
            }

            parallel {

                stage('Apply AWS') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_AWS_DIR}") {
                                withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                    sh 'terraform apply -auto-approve tfplan'
                                }
                            }
                        }
                    }
                }

                stage('Apply GCP') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_GCP_DIR}") {
                                withCredentials([
                                    file(credentialsId: 'gcp-sa-key', variable: 'GCP_KEY')
                                ]) {
                                    sh '''
                                        export GOOGLE_APPLICATION_CREDENTIALS=$GCP_KEY
                                        terraform apply -auto-approve tfplan
                                    '''
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Terraform Outputs') {
            parallel {

                stage('Output AWS') {
                    steps {
                        dir("${TF_AWS_DIR}") {
                            withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                sh 'terraform output -json > aws-tf-output.json'
                            }
                        }
                    }
                }

                stage('Output GCP') {
                    steps {
                        dir("${TF_GCP_DIR}") {
                            withCredentials([
                                file(credentialsId: 'gcp-sa-key', variable: 'GCP_KEY')
                            ]) {
                                sh '''
                                    export GOOGLE_APPLICATION_CREDENTIALS=$GCP_KEY
                                    terraform output -json > gcp-tf-output.json
                                '''
                            }
                        }
                    }
                }
            }
        }

        stage('Clone Ansible Project') {
            steps {
                dir("${env.WORKSPACE}/ansible") {
                    sh '''
                        git clone -b ansible \
                        https://github.com/GeraldOpitz/gogs-ansible .
                    '''
                }
            }
        }

        stage('Generate Ansible Inventory') {
            steps {
                script {
                    def appIpGCP = sh(
                        script: "terraform -chdir=${TF_GCP_DIR} output -raw vm_public_ip",
                        returnStdout: true
                    ).trim()

                    sh """
                        mkdir -p ansible/inventories
                        cat > ansible/inventories/inventory.ini <<EOL
[vm]
gogs_vm ansible_host=${appIpGCP} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOL
                    """
                }
            }
        }

        stage('Run Ansible - Deploy GCP') {
            steps {
                sshagent(['gcp-gogs-key']) {
                    sh '''
                        ansible-playbook \
                          -i ansible/inventories/inventory.ini \
                          ansible/playbooks.yml -vvv
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        failure {
            echo "Pipeline failed: review Terraform or SSH configuration."
        }
    }
}
