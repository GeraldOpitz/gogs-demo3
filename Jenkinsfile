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
                    sh 'rm -rf ./* ./.??* || true'
                    sh '''
                        git clone -b GOGS-5-Terraform-GCP \
                        https://github.com/GeraldOpitz/gogs-tf .
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
                                withCredentials([file(credentialsId: 'gcp-sa-key', variable: 'GCP_KEY')]) {
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
                                    file(credentialsId: 'gcp-gogs-key', variable: 'GCP_KEY')
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

            steps {
                input message: "¿Aplicar infraestructura en AWS y GCP?", ok: "yes"
            }
        }

        stage('Terraform Apply Parallel') {
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

        stage('Terraform Output') {
            parallel {

                stage('Output AWS') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_AWS_DIR}") {
                                withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                    sh '''
                                        terraform output
                                        terraform output -json > aws-tf-output.json
                                    '''
                                }
                            }
                        }
                    }
                }

                stage('Output GCP') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                            dir("${TF_GCP_DIR}") {
                                withCredentials([
                                    file(credentialsId: 'gcp-sa-key', variable: 'GCP_KEY')
                                ]) {
                                    sh '''
                                      export GOOGLE_APPLICATION_CREDENTIALS=$GCP_KEY
                                      terraform output
                                      terraform output -json > gcp-tf-output.json
                                    '''
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Clone Ansible Project') {
            steps {
                dir("${env.WORKSPACE}/ansible") {
                    sh 'rm -rf ./* ./.??* || true'
                    sh '''
                        git clone -b ansible \
                        https://github.com/GeraldOpitz/gogs-ansible .
                    '''
                }
            }
        }

        stage('Fetch Terraform Outputs') {
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
                stage('Fetch AWS Outputs') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                        script {
                            withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                sh """
                                    APP_IP=\$(terraform -chdir=${TF_AWS_DIR} output -raw ec2_public_ip)
                                    echo "\$APP_IP" > ${WORKSPACE}/ansible/app_ip_aws.txt
                                """
                            }
                        }
                    }
                }
            }

                stage('Fetch GCP Outputs') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                        script {
                            withCredentials([
                                file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
                            ]) {
                                sh """
                                    APP_IP=\$(terraform -chdir=${TF_GCP_DIR} output -raw vm_public_ip)
                                    echo "\$APP_IP" > ${WORKSPACE}/ansible/app_ip_gcp.txt
                                """
                            }
                        }
                    }
                }
            }
        }
    }

        stage('Generate Ansible Inventory') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                        script {
                            def appIpAWS = readFile("${WORKSPACE}/ansible/app_ip_aws.txt").trim()
                            def appIpGCP = readFile("${WORKSPACE}/ansible/app_ip_gcp.txt").trim()
                            sh """
                                mkdir -p ${WORKSPACE}/ansible/inventories
                                cat > ${WORKSPACE}/ansible/inventories/inventory.ini <<EOL
[ec2]
APP_EC2 ansible_host=${appIpAWS} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

APP_VM ansible_host=${appIpGCP} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOL
                            """
                        }
                    }
                }    
            }

        stage('Run Ansible - Deploy') {
            parallel {
                stage('Deploy AWS') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                        sshagent(['ec2-app-key']) {
                            sh '''
                                ansible-playbook \
                                  -i ansible/inventories/inventory.ini \
                                  ansible/playbooks.yml \
                                  -u ubuntu
                            '''
                        }
                    }
                }
            }

                stage('Deploy GCP') {
                    steps {
                        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                        sshagent(['gcp-gogs-key']) {
                            sh '''
                                ansible-playbook \
                                  -i ansible/inventories/inventory.ini \
                                  ansible/playbooks.yml \
                                  -u ubuntu
                            '''
                        }
                    }
                }
            }
        }
    }
}

    post {
        always {
            cleanWs()
        }
        failure {
            echo "Failed to create or configure AWS or GCP resources."
        }
    }
}
