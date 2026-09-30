# Spring Boot CI/CD with Jenkins and Argo CD

This project builds a Java 17 Spring Boot web app, publishes a container image to private Oracle Cloud Infrastructure Registry (OCIR), and deploys it through Argo CD to a three-node kubeadm Kubernetes cluster. The running app has two replicas and is exposed by a NodePort Service.

## How it works

`GitHub main` → `Jenkins` → `Maven tests` → `SonarQube analysis` → `OCIR image` → `Git manifest update` → `Argo CD` → `Kubernetes`

The Jenkinsfile configures `pollSCM('H/5 * * * *')` to check GitHub for changes about every five minutes; **Build Now** also works. Ordinary commits run the full pipeline. An automatically triggered build for Jenkins's own `ci: update deployment image to ...` commit skips the remaining stages, avoiding a build loop. No GitHub webhook is required for SCM polling.

The pipeline runs Maven and SonarQube in a private JDK 17 Maven agent, then uses the Jenkins host's Docker-compatible CLI (Podman in this environment) to build and push a versioned image. The SonarQube stage uploads analysis but does not enforce a quality gate. The [Dockerfile](spring-boot-app/Dockerfile) uses an Oracle Java 21 runtime, which can run the Java 17 application. Jenkins then commits the new image tag to [deployment.yml](spring-boot-app-manifests/deployment.yml). Argo CD auto-syncs the manifests; it does not build the application.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`spring-boot-app/`](spring-boot-app/) | Spring Boot source, tests, Dockerfile, and Jenkins pipeline. |
| [`spring-boot-app-manifests/`](spring-boot-app-manifests/) | Kubernetes Deployment and NodePort Service watched by Argo CD. |
| [`ci/maven-settings.xml`](ci/maven-settings.xml) | Maven proxy configuration for this environment. |
| [`Argo CD/argocd-basic.yaml`](Argo%20CD/argocd-basic.yaml) | Creates an operator-managed Argo CD **instance**, not the app deployment. |
| [`Argo CD/spring-boot-app-application.yaml`](Argo%20CD/spring-boot-app-application.yaml) | Optional YAML alternative to creating the Argo CD **Application** in the UI. |

## Setup

1. **Jenkins:** Create a **Pipeline script from SCM** job using repository `https://github.com/shravankumarinchur/Jenkins.git`, branch `*/main`, and script path `spring-boot-app/JenkinsFile` (capital `F`). Run it once with **Build Now** after setup. The host needs a working Docker-compatible CLI, GitHub access, and access to the private OCIR Maven-agent image configured in the Jenkinsfile.
2. **Credentials:** Add `OCIR` as **Username with password** (OCIR username and auth token), `sonarqube` as **Secret text**, and `github` as **Username with password** (GitHub username and a token allowed to push to `main`). The pipeline expects SonarQube on the Jenkins host at `http://127.0.0.1:9000/`. Adjust [`ci/maven-settings.xml`](ci/maven-settings.xml) if your Maven proxy or artifact mirror differs.
3. **Kubernetes:** Install the Argo CD Operator and create an Argo CD instance. The included `argocd-basic.yaml` is for that initial instance setup only. If required by the operator, label the `default` namespace so this instance can manage it:

   ```bash
   kubectl label namespace default argocd.argoproj.io/managed-by=argocd --overwrite
   ```

4. **Private image pull:** If missing, create a registry Secret named **`ocir-secret` in `default`**, matching the Deployment's `imagePullSecrets`. Use a valid OCIR auth token; never commit it to Git:

   ```bash
   read -r -s -p 'OCIR auth token: ' OCIR_AUTH_TOKEN
   echo
   kubectl -n default create secret docker-registry ocir-secret \
     --docker-server=ocir.us-ashburn-1.oci.oraclecloud.com \
     --docker-username='<YOUR_OCIR_USERNAME>' \
     --docker-password="$OCIR_AUTH_TOKEN"
   unset OCIR_AUTH_TOKEN
   ```

5. **Argo CD:** Create an Application in the UI (or apply `Argo CD/spring-boot-app-application.yaml`) with repository `https://github.com/shravankumarinchur/Jenkins.git`, revision `main`, path `spring-boot-app-manifests`, destination cluster `https://kubernetes.default.svc`, namespace `default`, and **automated sync**. The UI-created Application works; the YAML file need not also be applied. If the repository is private, configure Argo CD repository access. Publish the first image before syncing a new installation.

## Verify and open the app

```bash
kubectl -n default rollout status deployment/spring-boot-app
kubectl -n default get pods -l app=spring-boot-app
kubectl -n default get svc spring-boot-app-service
kubectl get nodes -o wide
```

Open `http://<REACHABLE_NODE_IP>:<NODE_PORT>/`. The NodePort is the number after the colon in the Service's `PORT(S)` column (for example, `80:30798/TCP` means browser port `30798`). The Service forwards to the app on port `8080`; the home page is `/`. NodePort must be reachable from your browser's network.

If Jenkins does not start after a push, inspect the job's **Polling Log** and confirm its repository, `main` branch, and script path. If pods show `ImagePullBackOff`, check the pod events and confirm that `ocir-secret` exists in `default` with credentials for the same OCIR hostname as the image.
