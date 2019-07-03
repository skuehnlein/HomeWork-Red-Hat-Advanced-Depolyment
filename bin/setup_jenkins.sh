#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git na311.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Set up Jenkins with sufficient resources
# TBD
oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=5Gi --param DISABLE_ADMINISTRATIVE_MONITORS=true -n ${GUID}-jenkins
oc rollout pause dc jenkins -n ${GUID}-jenkins
oc rollout pause dc jenkins -n ${GUID}-jenkins
oc set resources dc jenkins --limits=memory=4Gi,cpu=2 --requests=memory=2Gi,cpu=1 -n ${GUID}-jenkins
oc set probe dc/jenkins --readiness --failure-threshold=3 --initial-delay-seconds=120 --get-url=http://:8080/login --period-seconds=10 --success-threshold=1 --timeout-seconds=600 -n ${GUID}-jenkins
oc set probe dc/jenkins --liveness --failure-threshold=3 --initial-delay-seconds=120 --get-url=http://:8080/login --period-seconds=10 --success-threshold=1 --timeout-seconds=600 -n ${GUID}-jenkins
oc rollout resume dc jenkins -n ${GUID}-jenkins

# wait while jenkins is ready
while : ; do
    echo "Checking if Jenkins is Ready..."
    oc get pod -n ${GUID}-jenkins | grep -v deploy | grep "1/1"
    if [ $? == "1" ] 
      then 
        echo "Waiting 10 seconds..."
        sleep 10
      else 
        break 
    fi
done

# Create custom agent container image with skopeo
# TBD
oc new-build  -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\n
      USER root\nRUN yum -y install skopeo && yum clean all\n
      USER 1001' --name=jenkins-agent-appdev -n ${GUID}-jenkins

# wait while jenkins agent is ready
while : ; do
	echo "Checking if Jenkins-app-slave is Ready..."
	oc get pod -n ${GUID}-jenkins | grep 'agent' | grep "Completed"
	if [ $? == "0" ] 
      then 
		echo 'jenkins-agent-appdev build completed'
		break
	  else 
		echo 'Waiting 10 seconds...'
		sleep 10
	fi
done

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
# TBD
echo "apiVersion: v1
items:
- kind: "BuildConfig"
  apiVersion: "v1"
  metadata:
    name: "tasks-pipeline"
  spec:
    source:
      type: "Git"
      git:
        uri: "${REPO}"
    strategy:
      type: "JenkinsPipeline"
      jenkinsPipelineStrategy:
        jenkinsfilePath: Jenkinsfile
kind: List
metadata: []" | oc create -f - -n ${GUID}-jenkins

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done