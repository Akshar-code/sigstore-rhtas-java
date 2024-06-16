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
         // Environment setup steps...

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
            sh '''
               #!/bin/bash
               echo "Installing syft"
               curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

               echo "Generating SBOM"
               syft $IMAGE_DESTINATION -o spdx-json > sbom.spdx.json

               echo "Pushing SBOM to registry"
               cosign attach sbom --type spdx-json $IMAGE_DESTINATION sbom.spdx.json
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

               $COSIGN attest --identity-token=/var/run/sigstore/cosign/id-token --predicate=sbom.spdx.json -y --type=spdxjson $DIGEST_DESTINATION
            '''
            }
        }
        stage('Verify Artifacts'){
            sh '''
            $COSIGN verify  --certificate-identity=ci-builder@redhat.com  quay.io/rh-ee-akottuva/jenkins-sbom
            '''
        }

    }
}
