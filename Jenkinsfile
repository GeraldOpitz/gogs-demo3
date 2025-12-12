pipeline {
    agent any
    environment {
        TF_DIR = "${env.WORKSPACE}/terraform/environments/dev"
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
                        git clone -b GOGS-5-Terraform-Infrastructure-as-Code \
                        https://github.com/GeraldOpitz/gogs-tf .
                    '''
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir("${TF_DIR}") {
                    withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                        sh '''
                            echo "Starting Terraform"
                            terraform version
                            terraform init -backend-config="backend.hcl"
                        '''
                    }
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir("${TF_DIR}") {
                    withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                        sh '''
                            echo "Planning changes"
                            terraform plan -out=tfplan
                        '''
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
                script {
                    input message: "¿Do you wish to apply Terraform changes in ${env.BRANCH_NAME}? Type 'yes' to continue.", ok: "yes"
                    dir("${TF_DIR}") {
                        withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                            sh '''
                                echo "Applying changes"
                                terraform apply -auto-approve tfplan
                            '''
                        }
                    }
                }
            }
        }

        stage('Terraform Output') {
            steps {
                dir("${TF_DIR}") {
                    withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                        sh '''
                            echo "Mostrando Terraform Output:"
                            terraform output

                            echo "Generando tf-output.json..."
                            terraform output -json > tf-output.json
                        '''
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
            steps {
                script {
                    withAWS(credentials: 'aws-credentials', region: 'us-east-1') {
                        sh """
                            export APP_IP=\$(terraform -chdir=$TF_DIR output -raw ec2_public_ip)
                            echo "\$APP_IP" > ${WORKSPACE}/ansible/app_ip.txt
                        """
                    }
                }
            }
        }

        stage('Generate Ansible Inventory') {
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
                script {
                    def appIp = readFile("${WORKSPACE}/ansible/app_ip.txt").trim()
                    sh """
                        mkdir -p ${WORKSPACE}/ansible/inventories
                        cat > ${WORKSPACE}/ansible/inventories/inventory.ini <<EOL
[ec2]
APP_EC2 ansible_host=${appIp} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOL
                    """
                }
            }
        }

        stage('Run Ansible - Deploy') {
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
                script {
                    sshagent(['ec2-app-key']) {
                        sh """
                            set -e
                            ansible-playbook \
                                -i ${WORKSPACE}/ansible/inventories/inventory.ini \
                                ${WORKSPACE}/ansible/playbooks.yml \
                                -u ubuntu || exit_code=\$?

                            if [ "\$exit_code" = "4" ]; then
                                echo "Warnings only, continuing..."
                                exit 0
                            elif [ -n "\$exit_code" ]; then
                                exit \$exit_code
                            fi
                        """
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
            echo "Failed to create or configure resources."
        }
    }
}
