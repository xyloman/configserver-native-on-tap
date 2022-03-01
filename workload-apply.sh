#!/bin/bash

name=configserver

# Build the artifact using local maven resolution
./mvnw clean package -DskipTests

# Unzip the artifact to a directory that will be uploaded to an image registry using imgpkg
unzip ./target/*.jar -d ./target/src

# Use imgpkg to push the container to the local image registry
pushd ./target/src
  mkdir .imgpkg
  cat <<EOF > .imgpkg/images.yml
---
apiVersion: imgpkg.carvel.dev/v1alpha1
kind: ImagesLock
EOF
  imgpkg push --bundle dev.local:5000/${name} --file ./
popd

# Apply the Workload resource to the cluster
kubectl apply -f config/workload.yaml

# Tail the logs associated to the workload
tanzu apps workloads tail --timestamp ${name}