# Spring Boot based Java web application
 
This is a Spring Boot web application built with Java 17 and Maven 3.6.3 or newer. The build dependencies are defined in `pom.xml` in this directory.

This is a MVC architecture based application where controller returns a page with title and message attributes to the view.

## Execute the application locally and access it using your browser

Checkout the repo and move to the directory

```
git clone https://github.com/shravankumarinchur/Jenkins.git
cd Jenkins/spring-boot-app
```

Execute the Maven targets to generate the artifacts

```
mvn clean package
```

The above maven target stroes the artifacts to the `target` directory. You can either execute the artifact on your local machine
(or) run it as a Docker container.

** Note: To avoid issues with local setup, Java versions and other dependencies, I would recommend the docker way. **


### Execute locally (Java 17 or newer needed) and access the application on http://localhost:8080

```
java -jar target/spring-boot-web.jar
```

### The Docker way

The Dockerfile uses `container-registry.oracle.com/graalvm/jdk:21` as its runtime base image. This is Oracle Container Registry, which is separate from the private OCIR registry used by Jenkins to push the finished application image. If your environment requires authentication for the base image, log in to `container-registry.oracle.com` before building.

The Jenkins `maven-agent:v1` image contains JDK 17, Maven 3.6.3, and Git. Jenkins runs the container CLI on its host, so the Maven image does not need a Docker CLI or socket. The Java 17 build runs on the Java 21 runtime image in the Dockerfile. See the repository root README for Jenkins and Argo CD setup.

Build the Docker Image

```
docker build -t ultimate-cicd-pipeline:v1 .
```

```
docker run -d -p 8010:8080 -t ultimate-cicd-pipeline:v1
```

Hurray !! Access the application on `http://<ip-address>:8010`


## Next Steps

### Configure a Sonar Server locally

```
System Requirements
Java 17+ (Oracle JDK, OpenJDK, or AdoptOpenJDK)
Hardware Recommendations:
   Minimum 2 GB RAM
   2 CPU cores
sudo apt update && sudo apt install unzip -y
adduser sonarqube
wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-10.4.1.88267.zip
unzip *
chown -R sonarqube:sonarqube /opt/sonarqube
chmod -R 775 /opt/sonarqube
cd /opt/sonarqube/bin/linux-x86-64
./sonar.sh start
```

Hurray !! Now you can access the `SonarQube Server` on `http://<ip-address>:9000` 
