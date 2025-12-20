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
                        dir("${TF_AWS_DIR}") {
                            withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                sh 'terraform init -backend-config="backend.hcl"'
                            }
                        }
                    }
                }
                stage('Init GCP') {
                    steps {
                        dir("${TF_GCP_DIR}") {
                            withCredentials([file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
                                sh 'terraform init'
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
                        dir("${TF_AWS_DIR}") {
                            withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                sh '''
                                    echo "Planning AWS changes"
                                    terraform plan -out=tfplan
                                '''
                            }
                        }
                    }
                }

                stage('Plan GCP') {
                    steps {
                        dir("${TF_GCP_DIR}") {
                            withCredentials([
                                file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
                            ]) {
                                sh '''
                                    echo "Planning GCP changes"
                                    terraform plan -out=tfplan
                                '''
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
            parallel {

                stage('Apply AWS') {
                    steps {
                        script {
                            input message: "¿Do you wish to apply Terraform changes in AWS (${env.BRANCH_NAME})?",
                                ok: "yes"
                            dir("${TF_DIR_AWS}") {
                                withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                    sh '''
                                        terraform apply -auto-approve tfplan
                                    '''
                                }
                            }
                        }
                    }
                }

                stage('Apply GCP') {
                    steps {
                        script {
                            input message: "¿Do you wish to apply Terraform changes in GCP (${env.BRANCH_NAME})?",
                                ok: "yes"
                            dir("${TF_DIR_GCP}") {
                                sh '''
                                    terraform apply -auto-approve tfplan
                                '''
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
                        dir("${TF_AWS_DIR}") {
                            withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                                sh '''
                                    terraform output
                                    terraform output -json > tf-output-aws.json
                                '''
                            }
                        }
                    }
                }

                stage('Output GCP') {
                    steps {
                        dir("${TF_GCP_DIR}") {
                            withCredentials([
                                file(credentialsId: 'gcp-sa-key', variable: 'GOOGLE_APPLICATION_CREDENTIALS')
                            ]) {
                                sh '''
                                    terraform output
                                    terraform output -json > tf-output-gcp.json
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

                stage('Fetch GCP Outputs') {
                    steps {
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

        stage('Generate Ansible Inventories') {
            parallel {
                stage('AWS Inventory') {
                    steps {
                        script {
                            def appIp = readFile("${WORKSPACE}/ansible/app_ip_aws.txt").trim()
                            sh """
                                cat > ${WORKSPACE}/ansible/inventories/aws.ini <<EOF
    [ec2]
    APP_EC2 ansible_host=${appIp} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    EOF
                            """
                        }
                    }
                }

                stage('GCP Inventory') {
                    steps {
                        script {
                            def appIp = readFile("${WORKSPACE}/ansible/app_ip_gcp.txt").trim()
                            sh """
                                cat > ${WORKSPACE}/ansible/inventories/gcp.ini <<EOF
    [vm]
    APP_VM ansible_host=${appIp} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    EOF
                            """
                        }
                    }
                }
            }
        }

        stage('Run Ansible - Deploy') {
            parallel {
                stage('Deploy AWS') {
                    steps {
                        sshagent(['ec2-app-key']) {
                            sh '''
                                ansible-playbook \
                                  -i ansible/inventories/aws.ini \
                                  ansible/playbooks.yml \
                                  -u ubuntu
                            '''
                        }
                    }
                }

                stage('Deploy GCP') {
                    steps {
                        sshagent(['gcp-ssh-key']) {
                            sh '''
                                ansible-playbook \
                                  -i ansible/inventories/gcp.ini \
                                  ansible/playbooks.yml \
                                  -u ubuntu
                            '''
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
