

properties([
    parameters([
        string(defaultValue: 'quay.io/ablock/nonroot-jenkins-agent-maven:latest', description: 'Agent Image', name: 'AGENT_IMAGE'),
        string(description: 'Cluster Apps Domain', name: 'APPS_DOMAIN'),
        string(description: 'OIDC Issuer', name: 'OIDC_ISSUER'),
        string(defaultValue: 'trusted-artifact-signer', description: 'Client ID', name: 'CLIENT_ID'),
        string(defaultValue: 'trusted-artifact-signer', description: 'Keycloak Realm', name: 'KEYCLOAK_REALM'),
        string(defaultValue: '', description: 'Image Destination', name: 'IMAGE_DESTINATION'),
        string(defaultValue: 'registry-credentials', description: 'Registry Credentials', name: 'REGISTRY_CREDENTIALS')
    ])
])

def getBombasticToken() {
    return sh(script: "kubectl get secret oidc-token -n jenkins -o jsonpath='{.data.id-token}' | base64 --decode", returnStdout: true).trim()
}

podTemplate([
    label: 'non-root-jenkins-agent-maven',
    cloud: 'openshift',
    serviceAccount: 'nonroot-builder',
    containers: [
        containerTemplate(
            name: 'jnlp',
            image: "${params.AGENT_IMAGE}",
            alwaysPullImage: false,
            args: '${computer.jnlpmac} ${computer.name}'
        )
    ],
    volumes: [secretVolume(mountPath: '/var/run/sigstore/cosign',
        secretName: 'oidc-token'
    )]
]) {
    node('non-root-jenkins-agent-maven') {
stage('Setup Environment') {
        script {
            env.COSIGN_FULCIO_URL="https://fulcio-server-trusted-artifact-signer.${params.APPS_DOMAIN}"
            env.COSIGN_REKOR_URL="https://rekor-server-trusted-artifact-signer.${params.APPS_DOMAIN}"
            env.COSIGN_MIRROR="https://tuf-trusted-artifact-signer.${params.APPS_DOMAIN}"
            env.COSIGN_ROOT="https://tuf-trusted-artifact-signer.${params.APPS_DOMAIN}/root.json"
            env.COSIGN_OIDC_ISSUER="${params.OIDC_ISSUER}"
            env.COSIGN_OIDC_CLIENT_ID="${params.CLIENT_ID}"
            env.COSIGN_CERTIFICATE_OIDC_ISSUER="${params.OIDC_ISSUER}"
            env.COSIGN_YES="true"
            env.SIGSTORE_FULCIO_URL="https://fulcio-server-trusted-artifact-signer.${params.APPS_DOMAIN}"
            env.SIGSTORE_OIDC_CLIENT_ID="${params.CLIENT_ID}"
            env.SIGSTORE_OIDC_ISSUER="${params.OIDC_ISSUER}"
            env.SIGSTORE_REKOR_URL="https://rekor-server-trusted-artifact-signer.${params.APPS_DOMAIN}"
            env.REKOR_REKOR_SERVER="https://rekor-server-trusted-artifact-signer.${params.APPS_DOMAIN}"
            env.COSIGN="bin/cosign"
            env.REGISTRY=sh(script: "echo ${params.IMAGE_DESTINATION} | cut -d '/' -f1", returnStdout: true).trim()

            if(params.APPS_DOMAIN == "") {
                currentBuild.result = 'FAILURE'
                error('Parameter APPS_DOMAIN is not provided')
            }

            dir("bin") {
                sh '''
                    #!/bin/bash
                    echo "Downloading cosign"
                    curl -Lks -o cosign.gz https://cli-server-trusted-artifact-signer.$APPS_DOMAIN/clients/linux/cosign-amd64.gz
                    gzip -f -d cosign.gz
                    rm -f cosign.gz
                    chmod +x cosign
                '''
            }

            dir("tuf") {
                deleteDir()
            }

            // Fetch and verify Bombastic token
            env.BOMBASTIC_TOKEN = getBombasticToken()
            echo "Verifying Bombastic Token"
            if (env.BOMBASTIC_TOKEN) {
                echo "Bombastic Token (first 10 chars): ${env.BOMBASTIC_TOKEN.take(10)}..."
                echo "Bombastic Token length: ${env.BOMBASTIC_TOKEN.length()}"
                if (env.BOMBASTIC_TOKEN.startsWith("eyJ")) {
                    echo "Bombastic Token appears to be in the correct format (starts with 'eyJ')"
                } else {
                    error "Bombastic Token does not start with the expected prefix"
                }
            } else {
                error "Bombastic Token is null or empty"
            }

            sh '''
              $COSIGN initialize
            '''
            
            stash name: 'binaries', includes: 'bin/*'
        }
    }

        stage('Checkout') {
            checkout scm
        }

        stage('Build Application') {
            sh '''
              mvn clean package
            '''
        }

        stage('Build and Push Image') {
            withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: params.REGISTRY_CREDENTIALS, usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD']]) {
                sh '''
                   podman login -u $REGISTRY_USERNAME -p $REGISTRY_PASSWORD $REGISTRY
                   podman build -t $IMAGE_DESTINATION -f ./src/main/docker/Dockerfile.jvm .
                   podman push --digestfile=target/digest $IMAGE_DESTINATION
                '''
            }
        }

        stage('Fetch Bombastic Token') {
                script {
                    env.BOMBASTIC_TOKEN = getBombasticToken()
                }
            }

        stage('Generate and put SBOM in TPA') {
            withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: params.REGISTRY_CREDENTIALS, usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD']]) {
                sh '''
                    #!/bin/bash
                    echo "Installing syft"
                    
                    # Create a directory for syft installation
                    INSTALL_DIR="${WORKSPACE}/bin"
                    mkdir -p ${INSTALL_DIR}
                    
                    # Install syft
                    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b ${INSTALL_DIR}
                    
                    # Add the bin directory to PATH
                    export PATH=${INSTALL_DIR}:$PATH

                    # Check installation
                    echo "Checking syft installation"
                    syft version
                    
                    echo "Generating SBOM"
                    syft $IMAGE_DESTINATION -o cyclonedx-json@1.4 > sbom.cyclonedx.json
                    echo "Printing SBOM For testing"
                    cat sbom.cyclonedx.json
                    echo "Pushing SBOM to Quay repository"
                    SBOM_FILE="sbom.cyclonedx.json"
                    REPOSITORY="quay.io/${REGISTRY_USERNAME}/test"
                    UPLOAD_URL="${REPOSITORY}/manifests/latest"
                    
                    curl -u ${REGISTRY_USERNAME}:${REGISTRY_PASSWORD} -X PUT -H "Content-Type: application/vnd.quay.sbom.cyclonedx+json" --data-binary @${SBOM_FILE} ${UPLOAD_URL}
                    
                    echo "SBOM pushed successfully"
                    echo "SBOM RHDA Analysis"
                    curl -X POST https://rhda.rhcloud.com/api/v4/analysis \
                    -H "Accept: application/json" \
                    -H "Content-Type: application/vnd.cyclonedx+json" \
                    -H "rhda-source: test" \
                    --data @$SBOM_FILE
                    echo "Pushing SBOM to TPA"
                    curl -g -X 'PUT' \
                    'https://sbom-trusted-profile-analyzer.apps.cluster-bqcjr.sandbox1219.opentlc.com/api/v1/sbom?id=rhtas_testing' \
                    -H 'accept: */*' \
                    -H "Authorization: Bearer ${BOMBASTIC_TOKEN}" \
                    -H 'Content-Type: application/json' \
                    -d @$SBOM_FILE
                    echo "SBOM Pushed successfully to TPA"
                '''
            }
        }

        stage('Sign Artifacts') {
            unstash 'binaries'

            // Sign Jar
            sh '''
            $COSIGN sign-blob $(find target -maxdepth 1  -type f -name '*.jar') --identity-token=/var/run/sigstore/cosign/id-token
            '''

            // Sign Container Image and Attest SBOM
            withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: params.REGISTRY_CREDENTIALS, usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD']]) {
                sh '''
                   set +x

                   DIGEST_DESTINATION="$(echo $IMAGE_DESTINATION | cut -d \":\" -f1)@$(cat target/digest)"
                   $COSIGN login -u $REGISTRY_USERNAME -p $REGISTRY_PASSWORD $REGISTRY

                   $COSIGN sign --identity-token=/var/run/sigstore/cosign/id-token $DIGEST_DESTINATION

                   $COSIGN attest --identity-token=/var/run/sigstore/cosign/id-token --predicate=./target/classes/META-INF/maven/com.redhat/sigstore-rhtas-java/license.spdx.json -y --type=spdxjson $DIGEST_DESTINATION
                '''
            }
        }

        stage('Verify Signature') {
            sh '''
            $COSIGN verify  --certificate-identity=ci-builder@redhat.com  quay.io/rh-ee-akottuva/jenkins-sbom
            '''
        }
    }
}

