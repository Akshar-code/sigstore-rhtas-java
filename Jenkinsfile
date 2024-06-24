
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
            '${TPA_INSTANCE/api/v1/sbom?id=${SBOM_ID}' \
            -H 'accept: */*' \
            -H 'Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJwRmVsV0JGWFE3blNkRmlHQndoalpuNWFxbWs0T08wZGx4QWtIUU5ZLVZJIn0.eyJleHAiOjE3MTkyNzMwMzMsImlhdCI6MTcxOTI3MjczMywiYXV0aF90aW1lIjoxNzE5MjU5MDYyLCJqdGkiOiJiNTM4OGJhOS02ODY4LTQ2OTQtODUzOS01NzkyN2EwN2E2YWIiLCJpc3MiOiJodHRwczovL3Nzby10cnVzdGVkLXByb2ZpbGUtYW5hbHl6ZXIuYXBwcy5jbHVzdGVyLXZ4Mjg0LnNhbmRib3g1NTcub3BlbnRsYy5jb20vcmVhbG1zL2NoaWNrZW4iLCJhdWQiOiJhY2NvdW50Iiwic3ViIjoiNjVlYmUwNDUtMjljMi00ODU3LWI3ODEtYjVmMzIwMjMzOGUxIiwidHlwIjoiQmVhcmVyIiwiYXpwIjoiZnJvbnRlbmQiLCJzZXNzaW9uX3N0YXRlIjoiMzk5MzExN2MtZTMwZS00N2RlLTgwZjktNDJmMGQ1ZjljOGY1IiwiYWxsb3dlZC1vcmlnaW5zIjpbIioiXSwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbIm9mZmxpbmVfYWNjZXNzIiwiY2hpY2tlbi11c2VyIiwidW1hX2F1dGhvcml6YXRpb24iLCJjaGlja2VuLWFkbWluIiwiZGVmYXVsdC1yb2xlcy1jaGlja2VuIiwiY2hpY2tlbi1tYW5hZ2VyIl19LCJyZXNvdXJjZV9hY2Nlc3MiOnsiYWNjb3VudCI6eyJyb2xlcyI6WyJtYW5hZ2UtYWNjb3VudCIsIm1hbmFnZS1hY2NvdW50LWxpbmtzIiwidmlldy1wcm9maWxlIl19fSwic2NvcGUiOiJvcGVuaWQgcmVhZDpkb2N1bWVudCBwcm9maWxlIGVtYWlsIGRlbGV0ZTpkb2N1bWVudCBjcmVhdGU6ZG9jdW1lbnQiLCJzaWQiOiIzOTkzMTE3Yy1lMzBlLTQ3ZGUtODBmOS00MmYwZDVmOWM4ZjUiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsInByZWZlcnJlZF91c2VybmFtZSI6ImFkbWluIn0.hRJcIHDFKaLLwS0gJ76h69BwUw5AUiSq5_UEoEltFIVc_uLrCkZHsR3i2BSkYrLaG0-JvqTjTAOxKoRnN1jGh3-Op1uiIBh1xRKW236wsSjY7N3QFvmuGvgnp9o3Txe2h7FkOEkaZOIKXAKxSHMBXmnAQWVJwnhBaCLT0zeZt0NIb05pEYsZz2LCqm1-lnYTwzDE4JEdnJyZe5wb_mndHd5uXqVlbqe4NSyN7qQ-IF0OMfVi0ub3UJf380fcOuUp73tHgMC24z5_xrm85mY1MVjS1Im41YhtiYxneMNoAV52eQRUSRaYtXVrwFAbq9K4cqFIWxyORYvKayOTXohKkg'\
            -H 'Content-Type: application/json' \
            -d @$SBOM_FILE
            echo "SBOM Pushed succesfully to TPA"
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
// Step to verify Signature
stage('Verify Signature') {
            sh '''
            $COSIGN verify  --certificate-identity=ci-builder@redhat.com  quay.io/rh-ee-akottuva/jenkins-sbom
            '''
        }



    }
}
