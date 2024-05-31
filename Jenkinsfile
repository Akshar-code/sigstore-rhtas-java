properties([
    parameters([
        string(description: 'Cluster Apps Domain', name: 'APPS_DOMAIN'),
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
            image: "quay.io/ablock/nonroot-jenkins-agent-maven:latest",
            alwaysPullImage: true,
            args: '${computer.jnlpmac} ${computer.name}'
        ),
        containerTemplate(
            name: 'syft',
            image: 'quay.io/redhat-appstudio/syft:v0.105.1@sha256:1910b829997650c696881e5fc2fc654ddf3184c27edb1b2024e9cb2ba51ac431',
            ttyEnabled: true,
            command: 'cat'
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
            env.COSIGN_OIDC_ISSUER="https://keycloak.${params.APPS_DOMAIN}/realms/${params.KEYCLOAK_REALM}"
            env.COSIGN_OIDC_CLIENT_ID="${params.CLIENT_ID}"
            env.COSIGN_CERTIFICATE_OIDC_ISSUER="https://keycloak.${params.APPS_DOMAIN}/realms/${params.KEYCLOAK_REALM}"
            env.COSIGN_YES="true"
            env.SIGSTORE_FULCIO_URL="https://fulcio-server-trusted-artifact-signer.${params.APPS_DOMAIN}"
            env.SIGSTORE_OIDC_CLIENT_ID="${params.CLIENT_ID}"
            env.SIGSTORE_OIDC_ISSUER="https://keycloak.${params.APPS_DOMAIN}/realms/${params.KEYCLOAK_REALM}"
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

        stage('Sign Artifacts') {
            unstash 'binaries'

            // Sign Jar
            sh '''
            $COSIGN sign-blob $(find target -maxdepth 1  -type f -name '*.jar') --identity-token=/var/run/sigstore/cosign/id-token
            '''

            // Define DIGEST_DESTINATION
            env.DIGEST_DESTINATION = sh(script: '''
               echo "$(echo $IMAGE_DESTINATION | cut -d \":\" -f1)@$(cat target/digest)"
            ''', returnStdout: true).trim()

            // Sign Container Image and Attest SBOM
            withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: params.REGISTRY_CREDENTIALS, usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD']]) {
                sh '''
                   set +x

                   $COSIGN login -u $REGISTRY_USERNAME -p $REGISTRY_PASSWORD $REGISTRY

                   $COSIGN sign --identity-token=/var/run/sigstore/cosign/id-token $DIGEST_DESTINATION

                   $COSIGN attest --identity-token=/var/run/sigstore/cosign/id-token --predicate=./target/classes/META-INF/maven/com.redhat/sigstore-rhtas-java/license.spdx.json -y --type=spdxjson $DIGEST_DESTINATION
                '''
            }
        }

        // Step to verify Cosign signature
        stage('Verify Cosign Signature') {
            sh '''
            $COSIGN verify --identity-token=/var/run/sigstore/cosign/id-token $DIGEST_DESTINATION
            '''
        }

        // Step to generate SBOM using Syft
        stage('Generate SBOM') {
            container('syft') {
                sh '''
                syft $DIGEST_DESTINATION -o spdx-json=sbom.json
                '''
                archiveArtifacts artifacts: 'sbom.json', allowEmptyArchive: true
            }
        }

    }
}
