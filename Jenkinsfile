
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

        sh '''
          $COSIGN initialize
        '''
        
        stash name: 'binaries', includes: 'bin/*'

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
stage('Generate and Push SBOM') {
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
            syft $IMAGE_DESTINATION -o spdx-json > sbom.spdx.json
            echo "Printing SBOM For testing"
            cat sbom.spdx.json
            echo "Pushing SBOM to Quay repository"
            SBOM_FILE="sbom.spdx.json"
            REPOSITORY="quay.io/${REGISTRY_USERNAME}/test"
            UPLOAD_URL="${REPOSITORY}/manifests/latest"
            
            curl -u ${REGISTRY_USERNAME}:${REGISTRY_PASSWORD} -X PUT -H "Content-Type: application/vnd.quay.sbom.spdx+json" --data-binary @${SBOM_FILE} ${UPLOAD_URL}
            
            echo "SBOM pushed successfully"
            echo "SBOM RHDA Analysis"
            curl -X POST https://rhda.rhcloud.com/api/v4/analysis \
            -H "Accept: application/json" \
            -H "Content-Type: application/vnd.cyclonedx+json" \
            -H "rhda-source: test" \
            --data @sbom.spdx.json
        '''
    }
}
stage('RHDA'){
    sh '''
    https rhda.rhcloud.com/api/v4/analysis Accept:application/json Content-Type:application/vnd.cyclonedx+json rhda-source:test @$SBOM_FILE
    '''
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
stage('Retrieve SBOM from Quay') {
    withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: params.REGISTRY_CREDENTIALS, usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD']]) {
        sh '''
            #!/bin/bash
            echo "Retrieving SBOM from Quay repository"
            
            REPOSITORY="quay.io/${REGISTRY_USERNAME}/jenkins-sbom"
            ENCODED_REPOSITORY=$(echo "${REGISTRY_USERNAME}/jenkins-sbom" | jq -sRr @uri)
            
            # Get an authorization token
            TOKEN=$(curl -s -u ${REGISTRY_USERNAME}:${REGISTRY_PASSWORD} "https://quay.io/v2/auth?service=quay.io&scope=repository:${ENCODED_REPOSITORY}:pull" | grep -o '"token":"[^"]*' | grep -o '[^"]*$')
            
            if [ -z "$TOKEN" ]; then
                echo "Failed to get an authentication token"
                exit 1
            fi
            
            # Specify the digest of the SBOM (you need to get this from the upload process or repository listing)
            DIGEST=$DIGEST_DESTINATION # Replace with the actual digest of the SBOM

            # Download the SBOM
            curl -s -H "Authorization: Bearer ${TOKEN}" "https://quay.io/v2/${REGISTRY_USERNAME}/jenkins-sbom/blobs/sha256:${DIGEST}" -o sbom.spdx.json

            # Verify the SBOM file
            cat sbom.spdx.json
        '''
    }
}



    }
}
