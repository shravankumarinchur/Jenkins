# Jenkins to Argo CD: Spring Boot on Kubernetes

This repository builds a Java 21 Spring Boot app, publishes it to Oracle Cloud Infrastructure Registry (OCIR), and deploys it through Argo CD. The manifests are plain Kubernetes YAML; this project does not use Helm.

## What each file does

| File | Purpose |
| --- | --- |
| `spring-boot-app/JenkinsFile` | Builds, tests, scans, publishes the image, and commits its new tag to Git. |
| `spring-boot-app/Dockerfile` | Packages the built JAR with an Oracle Container Registry Java 21 runtime image. |
| `spring-boot-app-manifests/` | Kubernetes Deployment and Service watched by Argo CD. |
| `Argo CD/argocd-basic.yaml` | Creates the `example-argocd` Argo CD **instance** through the Argo CD Operator. It is for cluster setup, not application deployment. |
| `Argo CD/spring-boot-app-application.yaml` | Creates the Argo CD **Application** that watches `spring-boot-app-manifests/` and deploys the Spring Boot app. |
| `my-first-pipeline/Jenkinsfile` | Independent smoke test for a Jenkins Docker agent. |

The flow is: source commit → Jenkins build and test → SonarQube scan → image push to OCIR → Jenkins commits the image tag → Argo CD syncs the Deployment and Service. Jenkins skips the extra build triggered by its own image-tag commit.

## Jenkins prerequisites

Configure a **Pipeline script from SCM** job using Git with Repository URL `https://github.com/shravankumarinchur/Jenkins.git`, Branch Specifier `*/main`, and Script Path `spring-boot-app/JenkinsFile` (capital `F`). Jenkins normally looks for a root-level `Jenkinsfile`, so the Script Path matters. The job needs the Git, Docker Pipeline, and Credentials Binding plugins and a worker with a working `docker`-compatible CLI (Docker or Podman) that can run, build, and push images. The GitHub plugin is optional and only needed for the webhook setup described below. If the repository is private, select a credential that the Jenkins Git SCM configuration can use for checkout; the `github` Secret text credential below is used inside the pipeline for pushing, not automatically for SCM checkout.

The private OCIR image `ocir.us-ashburn-1.oci.oraclecloud.com/idsccoayafgg/my-project/maven-agent:v1` must contain JDK 21, Maven 3.6.3 or newer, and Git. Jenkins prints their versions in the Maven container and checks the container CLI on the host before building the application image. The Maven container does not need access to `/var/run/docker.sock`; the host builds and pushes the application image using the JAR in the shared workspace. That image's recipe is not in this repository, so verify its contents before the first run. Maven also needs access to Maven Central or your configured artifact mirror.

Create these Jenkins credentials with the exact IDs below:

| ID | Type | Used for |
| --- | --- | --- |
| `OCIR` | Username with password | Pulling the private Maven agent and pushing the finished app image. Use your OCIR username and auth token. |
| `sonarqube` | Secret text | SonarQube analysis token. |
| `github` | Secret text | GitHub personal access token with permission to write repository contents on `main`. |

## Triggering builds

The Jenkinsfile declares `pollSCM('H/5 * * * *')`, a trigger supported by this Jenkins installation. Commit and push this Jenkinsfile, then click **Build Now** once in the Jenkins job so Jenkins loads the trigger. Jenkins will check the configured Git repository for changes approximately every five minutes and run the job when it sees a new commit on `main`; no GitHub webhook or GitHub plugin is needed for this mode. **Build Now** works any time, including immediately after a manifest-only commit made by the pipeline; a manual build runs all stages. The pipeline skips an automatic build when the latest commit is its own `ci: update deployment image to ...` commit, preventing a build loop.

For **immediate** push-triggered builds instead of polling, install the Jenkins GitHub plugin and configure this job's **Build Triggers → GitHub hook trigger for GITScm polling**. Remove the `pollSCM` block from the Jenkinsfile when switching to this mode. Create a webhook in the GitHub repository under **Settings → Webhooks → Add webhook** with payload URL `https://YOUR-REACHABLE-JENKINS-URL/github-webhook/` (include the trailing slash and any Jenkins context path), content type `application/json`, and **Just the push event**. GitHub must be able to reach Jenkins from the internet. Check GitHub's **Recent Deliveries** for a successful delivery, then push a small change to `main` and check the Jenkins job's build history. The `github` Jenkins credential is not a substitute for a webhook. Do not enable both trigger methods for this job.

The SonarQube URL in `spring-boot-app/JenkinsFile` is `http://100.92.54.104:9000/`. Jenkins must be able to reach it. The scan uploads results; this pipeline does not yet enforce a SonarQube quality gate.

The application Dockerfile pulls `container-registry.oracle.com/graalvm/jdk:21`. Oracle Container Registry (`container-registry.oracle.com`) and your private OCIR (`ocir.us-ashburn-1.oci.oraclecloud.com`) are separate endpoints. The Jenkins worker must be able to pull the Java base image and push to OCIR.

## Cluster bootstrap

Your cluster already has the Argo CD Operator and the `example-argocd` instance running in the `argocd` namespace. You do not need to reapply `Argo CD/argocd-basic.yaml` to deploy this app. For a new cluster, install the operator, create the `argocd` namespace, then apply that file once to create the Argo CD instance. The file requests a `ClusterIP` server Service, matching the service type observed in your cluster.

The operator-managed Argo CD instance needs permission to deploy into the `default` namespace. Give it access once with:

```bash
kubectl label namespace default argocd.argoproj.io/managed-by=argocd --overwrite
```

If the GitHub repository is private, also configure its credentials in Argo CD so the repo server can read the manifests.

Before the app can pull its private image, create an OCIR registry Secret in the `default` namespace. Use the same OCIR username and auth token as the Jenkins `OCIR` credential:

```bash
read -r -s -p 'OCIR auth token: ' OCIR_AUTH_TOKEN
echo
kubectl -n default create secret docker-registry ocir-pull-secret \
  --docker-server=ocir.us-ashburn-1.oci.oraclecloud.com \
  --docker-username='YOUR_OCIR_USERNAME' \
  --docker-password="$OCIR_AUTH_TOKEN"
unset OCIR_AUTH_TOKEN
```

Commit and push the repository changes, then run Jenkins once. The initial manifest uses `replaceImageTag`; Jenkins replaces it with the image tag it just published. After that first successful push, apply the Argo CD Application from a checkout of this repository:

```bash
kubectl apply -f 'Argo CD/spring-boot-app-application.yaml'
kubectl -n argocd get applications.argoproj.io spring-boot-app
kubectl -n default get deployment spring-boot-app
kubectl -n default get pods -l app=spring-boot-app
kubectl -n default get service spring-boot-app-service
```

The Service is a NodePort Service; Kubernetes assigns its external node port. If the Application reports a sync or health error, inspect it with `kubectl -n argocd describe application spring-boot-app` and inspect the app pods with `kubectl -n default describe pods -l app=spring-boot-app`.
