#!groovy
podTemplate(
  label: "skopeo-pod",
  cloud: "openshift",
  inheritFrom: "maven",
  containers: [
    containerTemplate(
      name: "jnlp",
      image: "docker-registry.default.svc:5000/b3cf-jenkins/jenkins-agent-appdev",
      resourceRequestMemory: "1Gi",
      resourceLimitMemory: "2Gi",
      resourceRequestCpu: "1",
      resourceLimitCpu: "2"
    )
  ]
) {
  node('skopeo-pod') {
    // Define Maven Command to point to the correct
    // settings for our Nexus installation
    def mvnCmd = "mvn -s ../nexus_settings.xml"
    def prefix      = "b3cf"
    def devProject  = "${prefix}-tasks-dev"
    def prodProject = "${prefix}-tasks-prod"

    // Checkout Source Code.
    stage('Checkout Source') {
      checkout scm
    }

    // Build the Tasks Service
    dir('openshift-tasks') {
      // The following variables need to be defined at the top level
      // and not inside the scope of a stage - otherwise they would not
      // be accessible from other stages.
      // Extract version from the pom.xml
      def version = getVersionFromPom("pom.xml")

      // TBD Set the tag for the development image: version + build number
      def devTag = "${version}-" + currentBuild.number
      // Set the tag for the production image: version
      def prodTag = "${version}"

      // Using Maven build the war file
      // Do not run tests in this step
      stage('Build war') {
        echo "Building version ${devTag}"

        sh "${mvnCmd} clean package -Dmaven.test.skip=true"
      }

      // TBD: The next two stages should run in parallel

      // Using Maven run the unit tests
      stage('Unit Tests') {
        echo "Running Unit Tests"

        sh "${mvnCmd} test"
      }

      // Using Maven to call SonarQube for Code Analysis
      stage('Code Analysis') {
        echo "Running Code Analysis"

        sh "${mvnCmd} sonar:sonar -Dsonar.host.url=http://sonarqube-gpte-hw-cicd.apps.na311.openshift.opentlc.com -Dsonar.projectName=${JOB_BASE_NAME}-${devTag}"
      }

      // Publish the built war file to Nexus
      stage('Publish to Nexus') {
        echo "Publish to Nexus"

        sh "${mvnCmd} deploy -DskipTests=true -DaltDeploymentRepository=nexus::default::http://nexus3-gpte-hw-cicd.apps.na311.openshift.opentlc.com/repository/releases"
      }

      // Build the OpenShift Image in OpenShift and tag it.
      stage('Build and Tag OpenShift Image') {
        echo "Building OpenShift container image tasks:${devTag}"

        script {
          openshift.withCluster(){
            openshift.withProject("${devProject}") {
              openshift.selector ("bc" ,"tasks").startBuild("--from-file=./target/openshift-tasks.war" , "--wait=true")
              openshift.tag("tasks:latest", "tasks:${devTag}")
            }
          }
        }
      }

      // Deploy the built image to the Development Environment.
      stage('Deploy to Dev') {
        echo "Deploying container image to Development Project"

        script {
          openshift.withCluster() {
            openshift.withProject("${devProject}") {
              openshift.set("image", "dc/tasks", "tasks=docker-registry.default.svc:5000/${devProject}/tasks:${devTag}")
              openshift.set("env", "dc/tasks", "VERSION='${devTag} tasks-dev'")
              
              
              openshift.selector('configmap','tasks-config').delete()
              def configmap = openshift.create('configmap', 'tasks-config', '--from-file=./configuration/application-users.properties', '--from-file=./configuration/application-roles.properties' )

              openshift.selector("dc", "tasks").rollout().latest();
              
              // Wait for application to be deployed
              def dc = openshift.selector("dc", "tasks").object()
              def dc_version = dc.status.latestVersion
              def rc = openshift.selector("rc", "tasks-${dc_version}").object()
              
              echo "Waiting for ReplicationController tasks-${dc_version} to be ready"
              while (rc.spec.replicas != rc.status.readyReplicas) {
                sleep 15
                rc = openshift.selector("rc", "tasks-${dc_version}").object()
              }
            }
          }
        }
      }

      // Copy Image to Nexus container registry
      stage('Copy Image to Nexus container registry') {
        echo "Copy image to Nexus container registry"

        script {
          sh "skopeo copy --src-tls-verify=false --dest-tls-verify=false --src-creds openshift:\$(oc whoami -t) --dest-creds admin:redhat docker://docker-registry.default.svc:5000/${devProject}/tasks:${devTag} docker://nexus-registry.gpte-hw-cicd.svc.cluster.local:5000/tasks:${devTag}"

          openshift.withCluster() {
            openshift.withProject("${devProject}") {
              echo "Tag Image ${devProject}/tasks:${devTag} ${prodProject}/tasks:${prodTag}"                
              openshift.tag("${devProject}/tasks:${devTag}", "${prodProject}/tasks:${prodTag}")
            }
          }
        }
      }

      // Blue/Green Deployment into Production
      // -------------------------------------
      def destApp   = "tasks-green"
      def activeApp = ""

      stage('Blue/Green Production Deployment') {

        echo "Blue/Green Deployment"
        script {
          openshift.withCluster() {
            openshift.withProject("${prodProject}") {
              activeApp = openshift.selector("route", "tasks").object().spec.to.name
              if (activeApp == "tasks-green") {
                destApp = "tasks-blue"
              }
           
              echo "Active Application:      " + activeApp
              echo "Destination Application: " + destApp
              
              // Deploy the inactive application.
              
    
              openshift.set("env", "dc/${destApp}", "VERSION='${prodTag} ${destApp}'")
              openshift.set("image", "dc/${destApp}", "${destApp}=docker-registry.default.svc:5000/${prodProject}/tasks:${prodTag}")
              
              openshift.selector("configmap", "${destApp}-config").delete()
              def configmap = openshift.create("configmap","${destApp}-config","--from-file=./configuration/application-users.properties", "--from-file=./configuration/application-roles.properties")
              
              openshift.selector("dc", "${destApp}").rollout().latest();

              
              // Wait for application to be deployed
              def dc_prod = openshift.selector("dc", "${destApp}").object()
              def dc_version = dc_prod.status.latestVersion
              def rc_prod = openshift.selector("rc", "${destApp}-${dc_version}").object()
              echo "Waiting for ${destApp} to be ready"
              while (rc_prod.spec.replicas != rc_prod.status.readyReplicas) {
                sleep 5
                rc_prod = openshift.selector("rc", "${destApp}-${dc_version}").object()
              }
            }
          }
        }
     }


      stage('Switch over to new Version') {
        echo "Switching Production application to ${destApp}."
        script {
          openshift.withCluster(){
            openshift.withProject("${prodProject}") {
              def route = openshift.selector("route/tasks").object()
              route.spec.to.name="${destApp}"
              openshift.apply(route)
            }
          }
        }
      }
    }
  }
}

// Convenience Functions to read version from the pom.xml
// Do not change anything below this line.
// --------------------------------------------------------
def getVersionFromPom(pom) {
  def matcher = readFile(pom) =~ '<version>(.+)</version>'
  matcher ? matcher[0][1] : null
}