# Example Spring (Native) Cloud Config Server on Tanzu Application Platform

The purpose of this repository is to demonstrate a Spring Native Spring Cloud Config Server running on Tanzu Application Platform.  Prior to starting this guide checkout the first write up of running a [configserver-on-tap](https://github.com/xyloman/configserver-on-tap).  Specifically ensure that `ServiceBinding` and `Secret` resources have been configured to be bound to the workload. 

This guide draws directly from the spring-native [Getting started with Buildpacks](https://docs.spring.io/spring-native/docs/current/reference/htmlsingle/#getting-started-buildpacks) documentation.

## Setup Kubernetes environment

Setup a kind environment locally if you desire to test locally.  The guide was written using the setup documented here: https://github.com/xyloman/tanzu-application-platform-local-setup

Setup the kubernetes environment to have the secrets necessary for the configserver to startup: https://github.com/xyloman/configserver-on-tap#configure-the-secrets-in-kubernetes


## Update pom.xml

If attempting to perform this on an existing application make sure to follow these key steps:
1. [Validate Spring Boot Version](https://docs.spring.io/spring-native/docs/current/reference/htmlsingle/#_validate_spring_boot_version)
1. [Add Spring Native Dependency](https://docs.spring.io/spring-native/docs/current/reference/htmlsingle/#_add_the_spring_native_dependency)
1. [Add the Spring AOT Plugin](https://docs.spring.io/spring-native/docs/current/reference/htmlsingle/#_add_the_spring_aot_plugin)
1. [Maven Repositories](https://docs.spring.io/spring-native/docs/current/reference/htmlsingle/#_maven_repository) **Note:** make sure to do both `repository` and `pluginRepository` sections.
1. **NOTE:** When using spring-native the need to [exclude spring-cloud-bindings](https://github.com/xyloman/configserver-on-tap#pomxml) appears to not be necessary.

### Comprehensive pom.xml Updates

Add the `org.springframework.experimental:spring-native` artifact.

```xml
<dependency>
    <groupId>org.springframework.experimental</groupId>
    <artifactId>spring-native</artifactId>
    <version>${spring-native.version}</version>
</dependency>
```

Configure the build plugin section to include `org.springframework.boot:spring-boot-maven-plugin` and `org.springframework.experimental:spring-aot-maven-plugin`.
```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
        </plugin>
        <plugin>
            <groupId>org.springframework.experimental</groupId>
            <artifactId>spring-aot-maven-plugin</artifactId>
            <version>${spring-native.version}</version>
            <executions>
                <execution>
                    <id>generate</id>
                    <goals>
                        <goal>generate</goal>
                    </goals>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

Update the plugin and dependency repositories to include spring-release: 
```xml
<repositories>
    <repository>
        <id>spring-releases</id>
        <url>https://repo.spring.io/release/</url>
        <releases>
            <enabled>true</enabled>
        </releases>
        <snapshots>
            <enabled>false</enabled>
        </snapshots>
    </repository>
</repositories>
<pluginRepositories>
    <pluginRepository>
        <id>spring-release</id>
        <name>Spring release</name>
        <url>https://repo.spring.io/release</url>
    </pluginRepository>
</pluginRepositories>
```

## Update workload.yaml

We will leverage Tanzu Build Service as apart of Tanzu Application Platform to build our container.  Therefore, we will need to build on the [workload.yaml](config/workload.yaml). We need to give a hint through the `build.env` section of the configuration.  This hint will tell the build service that our application is a NATIVE JAVA application.  This is similar to [pack cli](https://docs.vmware.com/en/VMware-Tanzu-Buildpacks/services/tanzu-buildpacks/GUID-java-native-image-java-native-image-buildpack.html) or the [spring-boot-maven-plugin](https://docs.spring.io/spring-native/docs/current/reference/htmlsingle/#_enable_native_image_support)

```yaml
  ...
  build:
    env:
    - name: BP_NATIVE_IMAGE
      value: "true"
  ...
```

In addition you could also update the version of Java to 17, while not required, could have further performance improvements:

```yaml
  ...
  build:
    env:
    - name: BP_NATIVE_IMAGE
      value: "true"
    - name: BP_JVM_VERSION
      value: "17.*"
  ...
```

This will allow for Tanzu Build Service to control the updating of GraalVM and Tiny Base Image based upon what is installed and configured for your instance of Tanzu Application Platform.  It also will allow for the latest version of GraalVM applied directly to your application when those updates are pulled for [Tanzu Network](https://network.tanzu.vmware.com/products/tbs-dependencies/).  When the source layer or the other image layers are updated the supply chain will be invoked ensuring that everything is up to date for the published image in the registry. 

In this example we are needing to configure the Encryption Key and the Git Authentication secrets and bind them to our application.  Unlike non-native workloads we will need to set the `"org.springframework.cloud.bindings.boot.enable"` environment set equal to `"true"`.  This is not required with in non-native mode because the spring cloud bindings comes enabled by default.  We will also need to include the `spring-cloud-bindings` dependency and not exclude it with the `spring-boot-maven-plugin` like we did for a non-native workload.

```yaml
  env:
    - name: "org.springframework.cloud.bindings.boot.enable"
      value: "true"
```

## Build and Run the Workload

At the time of this writing the Tanzu CLI version `0.4.1` which ships with TAP `1.0.1` had the following issues with native workloads:
- Ensuring the `build.env` section of the `config/workload.yaml` is included when performing `tanzu apps workloads apply`
- Support `live-update` flag of the `tanzu apps workloads apply` when flag `BP_NATIVE_IMAGE` was equal to true

### Steps to Build and Run without Tilt

These steps will make use of the `mvnw` (included with this repo), [imgpkg](https://carvel.dev/imgpkg/), kubectl, and tanzu CLIs.

#### Stage the local changes associated to the application
```bash
# Build the artifact using local maven resolution
./mvnw clean package -DskipTests

# Unzip the artifact to a directory that will be uploaded to an image registry using imgpkg
unzip ./target/*.jar -d ./target/src
```
#### Use imgpkg to push the container to the local image registry
```bash
pushd ./target/src
  mkdir .imgpkg
  cat <<EOF > .imgpkg/images.yml
---
apiVersion: imgpkg.carvel.dev/v1alpha1
kind: ImagesLock
EOF
  imgpkg push --bundle dev.local:5000/${name} --file ./
popd
```

#### Apply the Workload resource to the cluster
```bash
kubectl apply -f config/workload.yaml
```

Ensure that the `workload.yaml` has the changes referenced earlier in the `build.env`.  When building in this fashion point to the source image by configuring `spec.source.image` equal to `dev.local:5000/configserver:latest` which will create an `ImageRepository` resource when this workload is applied.  This is a slight modification from the `GitRepository` resource that would have been created whith `spec.source.git`.  The `ImageRepository` resource will poll the configured URI every minute for an image update. The script [workload-apply.sh](workload-apply.sh) will build all of the changes that have been made locally and publish the source to image repository configured.  When the ImageRepository detects the change it will produce a new version which will cause Tanzu Build Service to build a new container image with the modified source.