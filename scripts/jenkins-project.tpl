<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.42">
  <actions>
    <org.jenkinsci.plugins.pipeline.modeldefinition.actions.DeclarativeJobAction plugin="pipeline-model-definition@1.9.2"/>
    <org.jenkinsci.plugins.pipeline.modeldefinition.actions.DeclarativeJobPropertyTrackerAction plugin="pipeline-model-definition@1.9.2">
      <jobProperties/>
      <triggers/>
      <parameters/>
      <options/>
    </org.jenkinsci.plugins.pipeline.modeldefinition.actions.DeclarativeJobPropertyTrackerAction>
  </actions>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.93">
    <script>pipeline {
  environment {
    PROJECT_GITHUB = &quot;https://github.com/opencloudcx-riva/react-microservice-template.git&quot;
	PROJECT_NAME   = &quot;react-microservice-template&quot;
	IMAGE_NAME     = &quot;react-microservice-template-app&quot;
	BUILD_NUMBER   = &quot;demo&quot;
    REGISTRY       = &quot;index.docker.io&quot;
    REPOSITORY     = &quot;rivasolutionsinc&quot;
    BRANCH         = &quot;main&quot;
  }
  agent {
    kubernetes {
      label &apos;react-microservice-template-build&apos;
      yaml &quot;&quot;&quot;
kind: Pod
metadata:
  name: kaniko
spec:
  containers:
  - name: java-builder
    image: maven
    command:
      - sleep
    args:
      - 99d
  - name: node-builder
    image: node:16.13.2-alpine3.15
    command:
      - sleep
    resources:
      requests:
        ephemeral-storage: &quot;4Gi&quot;
      limits:
        ephemeral-storage: &quot;8Gi&quot;
    args:
      - 99d
  - name: crane
    workingDir: /home/jenkins
    image: gcr.io/go-containerregistry/crane:debug
    imagePullPolicy: Always
    command:
    - /busybox/cat
    tty: true
    volumeMounts:
      - name: jenkins-docker-cfg
        mountPath: /root/.docker/
  - name: alpine
    workingDir: /home/jenkins
    image: alpine:latest
    imagePullPolicy: Always
    command:
    - /bin/cat
    tty: true
  - name: jnlp
    workingDir: /home/jenkins
  - name: kaniko
    workingDir: /home/jenkins
    image: gcr.io/kaniko-project/executor:debug
    imagePullPolicy: Always
    command:
    - /busybox/cat
    tty: true
    volumeMounts:
      - name: jenkins-docker-cfg
        mountPath: /kaniko/.docker
  volumes:
  - name: jenkins-docker-cfg
    projected:
      sources:
      - secret:
          name: riva-dockerhub
          items:
            - key: .dockerconfigjson
              path: config.json
&quot;&quot;&quot;
    }
  }
  stages {
    stage(&apos;Checkout&apos;) {
      steps {
        git branch: env.BRANCH, url: env.PROJECT_GITHUB
        }
    }
    stage(&apos;Install Node Modules&apos;) {
      steps {
        container(&apos;node-builder&apos;) {
            script {
              sh &apos;yarn install&apos;
            }
        }
      }
    }
    stage(&apos;Lint Branch&apos;) {
      steps {
        container(&apos;node-builder&apos;) {
          sh &apos;yarn run lint&apos;
        }
      }
    }
    stage(&apos;Unit Tests&apos;) {
      steps {
        container(&apos;node-builder&apos;) {
          sh &apos;yarn run test:unit&apos;
        }
      }
    }
     stage(&apos;Sonarqube Code Scan&apos;) {
      options {
        timeout(time: 1, unit: &apos;HOURS&apos;)
      }
      steps {
        container(&apos;java-builder&apos;) {
          script {
            scannerHome = tool &apos;SonarScanner&apos;
            projectKey = env.PROJECT_NAME
            mainBranch = env.BRANCH
            appVersion = env.BUILD_NUMBER
            withSonarQubeEnv(&quot;sonarqube&quot;) {
              sh &quot;$${scannerHome}/bin/sonar-scanner \
              -Dsonar.projectName=\&quot;$${projectKey}: ($${mainBranch})\&quot; \
              -Dsonar.projectVersion=\&quot;$${appVersion}\&quot; \
              -Dsonar.projectKey=$${projectKey}:$${mainBranch} \
              -Dsonar.sources=src \
              -Dsonar.inclusions=src/**/* \
              -Dsonar.exclusions=src/__mocks__/**/*,src/setupTests.ts,src/libs/**/*,src/**/*.test.tsx,src/**/*.test.ts \
              -Dsonar.tests=src \
              -Dsonar.test.inclusions=src/**/*.test.tsx,src/**/*.test.ts \
              -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
              -Dsonar.typescript.lcov.reportPaths=coverage/lcov.info&quot;
            }
          }
        }
      }
    }
    stage(&apos;Sonarqube Quality Gate&apos;) {
      options {
        timeout(time: 1, unit: &apos;MINUTES&apos;)
        retry(3)
      }
      steps {
        container(&apos;java-builder&apos;) {
          script {
            qg = waitForQualityGate()
            if (qg.status != &apos;OK&apos;) {
              error &quot;Pipeline aborted due to quality gate failure: $${qg.status}&quot;
            }
            echo currentBuild.result
          }
        }
      }
    }   
    stage(&apos;Build image and create tarball&apos;) {
      environment {
        PATH        = &quot;/busybox:/kaniko:$PATH&quot;
      }
      steps {
        container(name: &apos;kaniko&apos;, shell: &apos;/busybox/sh&apos;) {
            
          sh &apos;&apos;&apos;#!/busybox/sh
            /kaniko/executor --context `pwd` --verbosity debug --no-push --destination $${REGISTRY}/$${REPOSITORY}/$${IMAGE_NAME} --tarPath image.tar
          &apos;&apos;&apos;
        }
      }
    }
    stage(&quot;Grype scans of tarball&quot;) {
      steps { 
        container(name: &apos;alpine&apos;) {      
          sh &apos;apk add bash curl&apos;
          sh &apos;curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin&apos;
          sh &apos;grype image.tar --output table&apos;
        }
      }
    }
    stage(&quot;Push image to repository&quot;) {
      steps {
        container(name: &apos;crane&apos;) {
		  sh &apos;crane push image.tar $${REGISTRY}/$${REPOSITORY}/$${IMAGE_NAME}:$${BUILD_NUMBER}&apos;
        }
      } 
    }
  }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>