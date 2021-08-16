# Dogfooding Cluster

The dogfooding runs the instance of Tekton that is used for all the CI/CD needs of Tekton itself.The dogfooding resources which are applied to a tekton cluster are stored in [tektoncd/plumbing](https://github.com/tektoncd/plumbing/tree/master/tekton) repo.

**Note: This cluster is maintaned by tekton community. The instructions below are just for POC.**

### Prerequisites 

- Kubernetes cluster
- Kustomize [binaries](https://kubectl.docs.kubernetes.io/installation/kustomize/binaries/)

### Install Tekton

```bash
TEKTON_PIPELINE_VERSION='v0.19.0'
TEKTON_TRIGGERS_VERSION='v0.10.2'
TEKTON_DASHBOARD_VERSION='v0.12.0'
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/${TEKTON_PIPELINE_VERSION}/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/${TEKTON_TRIGGERS_VERSION}/release.yaml
kubectl apply -f https://github.com/tektoncd/dashboard/releases/download/${TEKTON_DASHBOARD_VERSION}/tekton-dashboard-release.yaml
```
Check if all pods are up
```bash
~# kubectl get all -n tekton-pipelines
NAME                                               READY   STATUS    RESTARTS   AGE
pod/tekton-dashboard-56c78f485b-zcq88              1/1     Running   0          48s
pod/tekton-pipelines-controller-5cdb46974f-mksk4   1/1     Running   0          58s
pod/tekton-pipelines-webhook-6479d769ff-8r5kp      1/1     Running   0          58s
pod/tekton-triggers-controller-5994f6c94b-2h96c    1/1     Running   0          52s
pod/tekton-triggers-webhook-68c7866d8-s6hr8        1/1     Running   0          52s

NAME                                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                              AGE
service/tekton-dashboard              ClusterIP   10.96.118.142    <none>        9097/TCP                             48s
service/tekton-pipelines-controller   ClusterIP   10.99.182.58     <none>        9090/TCP,8080/TCP                    58s
service/tekton-pipelines-webhook      ClusterIP   10.109.2.87      <none>        9090/TCP,8008/TCP,443/TCP,8080/TCP   56s
service/tekton-triggers-controller    ClusterIP   10.103.183.249   <none>        9090/TCP                             52s
service/tekton-triggers-webhook       ClusterIP   10.96.189.183    <none>        443/TCP                              52s

NAME                                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/tekton-dashboard              1/1     1            1           48s
deployment.apps/tekton-pipelines-controller   1/1     1            1           58s
deployment.apps/tekton-pipelines-webhook      1/1     1            1           58s
deployment.apps/tekton-triggers-controller    1/1     1            1           52s
deployment.apps/tekton-triggers-webhook       1/1     1            1           52s

NAME                                                     DESIRED   CURRENT   READY   AGE
replicaset.apps/tekton-dashboard-56c78f485b              1         1         1       48s
replicaset.apps/tekton-pipelines-controller-5cdb46974f   1         1         1       58s
replicaset.apps/tekton-pipelines-webhook-6479d769ff      1         1         1       58s
replicaset.apps/tekton-triggers-controller-5994f6c94b    1         1         1       52s
replicaset.apps/tekton-triggers-webhook-68c7866d8        1         1         1       52s

NAME                                                           REFERENCE                             TARGETS          MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/tekton-pipelines-webhook   Deployment/tekton-pipelines-webhook   <unknown>/100%   1         5         1          58s
```
Make dashboard accessible from outside by change service type from `ClusterIP` to `NodePort`

**Note: Make sure the port is open in firewall and in security group**
```
kubectl edit service/tekton-dashboard -n tekton-pipelines
```
```diff
   ports:
   - name: http
+    nodePort: 32323
     port: 9097
     protocol: TCP
     targetPort: 9097
@@ -70,6 +83,6 @@ spec:
     app.kubernetes.io/name: dashboard
     app.kubernetes.io/part-of: tekton-dashboard
   sessionAffinity: None
-  type: ClusterIP
+  type: NodePort
 status:
   loadBalancer: {}
```
Access the dashboard at `<master node's public-ip>:<port>`

### Deploy Dogfooding Resources

```bash
kustomize build tekton/resources|kubectl create -f -

# create git-cone task
kubectl create -n bastion-p -f https://raw.githubusercontent.com/tektoncd/catalog/master/task/git-clone/0.3/git-clone.yaml
```

### Resources, Tasks & Pipeline to run e2e test on remote cluster

The pipeline created should be able to build, deploy, test and cleanup tekton pipelines on remote cluster configured by kubeconfig file.

#### Resource for tektoncd/pipelines repo

```yaml
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: tekton-pipeline-source
spec:
  type: git
  params:
    - name: revision
      value: master
    - name: url
      value: https://github.com/tektoncd/pipeline
```

#### Resource for tektoncd/plumbing repo

```yaml
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: plumbing-source
spec:
  type: git
  params:
    - name: revision
      value: master
    - name: url
      value: https://github.com/tektoncd/plumbing
```

#### Task to build and deploy tektoncd/pipelines

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: deploy-pipeline-on-ppc64le
spec:
  params:
  - name: package
    description: package to install
  - name: container-registry
    description: container registry used to publish build images
  - name: kubeconfig-secret
    description: secret with kubeconfig for remote cluster
  - name: target-arch
    description: target architecture for tests (s390x, ppc64le, arm64)
  resources:
    inputs:
    - name: tekton-project-source
      type: git
      targetPath: src/$(params.package)
  steps:
  - name: deploy
    workingdir: /workspace/src/$(params.package)
    image: gcr.io/tekton-releases/dogfooding/test-runner:latest
    env:
    - name: GOPATH
      value: /workspace
    - name: KO_DOCKER_REPO
      value: $(params.container-registry)
    - name: KUBECONFIG
      value: /root/.kube/config
    command:
    - /bin/bash
    args:
    - -ce
    - |
      arch
      ko apply --insecure-registry --platform=linux/$(params.target-arch) -j 1 -f config/
      kubectl wait -n tekton-pipelines --for=condition=ready pods --all --timeout=120s
    volumeMounts:
    - name: kubeconfig-secret
      mountPath: /root/.kube
  volumes:
  - name: kubeconfig-secret
    secret:
      secretName: $(params.kubeconfig-secret)
```

#### Task to run e2e tests for tektoncd/pipelines

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: test-pipeline-on-ppc64le
spec:
  params:
  - name: package
    description: package (and its children) under test
  - name: tests-path
    description: path to the tests within "tests" git resource
    default: ./test
  - name: timeout
    description: timeout for the go test runner
    default: 30m
  - name: container-registry
    description: container registry used to publish build images
  - name: tags
    default: e2e
  - name: kubeconfig-secret
    description: secret with kubeconfig for remote cluster
  - name: target-arch
    description: target architecture for tests (s390x, ppc64le, arm64)
  resources:
    inputs:
    - name: tekton-project-source
      type: git
      targetPath: src/$(params.package)
    - name: plumbing-source
      type: git
  steps:
  - name: e2e-test
    workingdir: /workspace/src/$(params.package)
    image: gcr.io/tekton-releases/dogfooding/test-runner:latest
    env:
    - name: REPO_ROOT_DIR
      value: $(resources.inputs.tekton-project-source.path)
    - name: GOPATH
      value: /workspace
    - name: KO_DOCKER_REPO
      value: $(params.container-registry)
    - name: KUBECONFIG
      value: /root/.kube/config
    - name: TEST_RUNTIME_ARCH
      value: $(params.target-arch)
    - name: SYSTEM_NAMESPACE
      value: tekton-pipelines
    command:
    - /bin/bash
    args:
    - -ce
    - |
      source $(resources.inputs.plumbing-source.path)/scripts/library.sh
      sed -i 's/timeout  = 10/timeout  = 20/g' test/wait.go
      header "Running Go $(params.tags) tests"
      report_go_test -v -count=1 -tags=$(params.tags) -timeout=$(params.timeout) $(params.tests-path) -kubeconfig /root/.kube/config
    volumeMounts:
    - name: kubeconfig-secret
      mountPath: /root/.kube
  volumes:
  - name: kubeconfig-secret
    secret:
      secretName: $(params.kubeconfig-secret)
```

#### Task to clean up resources created by tektoncd/pipelines

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: cleanup-pipeline-on-ppc64le
spec:
  params:
  - name: package
  - name: resources
    description: space separated list of resources to be deleted
    default: "conditions pipelineresources tasks pipelines taskruns pipelineruns"
  - name: kubeconfig-secret
    description: secret with kubeconfig for remote cluster
  resources:
    inputs:
    - name: plumbing-source
      type: git
    - name: tekton-project-source
      type: git
      targetPath: src/$(params.package)
  steps:
  - name: cleanup-resources
    image: gcr.io/tekton-releases/dogfooding/test-runner:latest
    env:
    - name: KUBECONFIG
      value: /root/.kube/config
    command:
    - /bin/sh
    args:
    - -ce
    - |
      kubectl delete ns -l tekton.dev/test-e2e=true
      for res in $(params.resources); do
        kubectl delete --ignore-not-found=true ${res}.tekton.dev --all || return true
      done
    volumeMounts:
    - name: kubeconfig-secret
      mountPath: /root/.kube
  - name: uninstall-tekton-project
    image: gcr.io/tekton-releases/dogfooding/test-runner:latest
    workingdir: /workspace/src/$(params.package)
    env:
    - name: KUBECONFIG
      value: /root/.kube/config
    command:
    - /bin/bash
    args:
    - -ce
    - |
      source $(resources.inputs.plumbing-source.path)/scripts/library.sh
      ko delete --ignore-not-found=true -f config/
      wait_until_object_does_not_exist namespace tekton-pipelines
    volumeMounts:
    - name: kubeconfig-secret
      mountPath: /root/.kube
  volumes:
  - name: kubeconfig-secret
    secret:
      secretName: $(params.kubeconfig-secret)
```

#### Pipeline to deploy, test & clean

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: deploy-test-clean-pipeline-on-ppc64le
spec:
  tasks:
    - name: deploy-pipeline
      taskRef:
        name: deploy-pipeline-on-ppc64le
      params:
        - name: package
          value: $(params.package)
        - name: container-registry
          value: $(params.container-registry)
        - name: kubeconfig-secret
          value: $(params.kubeconfig-secret)
        - name: target-arch
          value: $(params.target-arch)
      resources:
        inputs:
          - name: tekton-project-source
            resource: tekton-pipeline-source
    - name: e2e-test-pipeline
      runAfter:
        - deploy-pipeline
      taskRef:
        name: test-pipeline-on-ppc64le
      params:
        - name: package
          value: $(params.package)
        - name: container-registry
          value: $(params.container-registry)
        - name: kubeconfig-secret
          value: $(params.kubeconfig-secret)
        - name: target-arch
          value: $(params.target-arch)
      resources:
        inputs:
          - name: plumbing-source
            resource: plumbing-source
          - name: tekton-project-source
            resource: tekton-pipeline-source
  finally:
    - name: clean-pipeline-on-ppc64le
      taskRef:
        name: cleanup-pipeline-on-ppc64le
      params:
        - name: package
          value: $(params.package)
        - name: resources
          value: $(params.resources)
        - name: kubeconfig-secret
          value: $(params.kubeconfig-secret)
      resources:
        inputs:
          - name: plumbing-source
            resource: plumbing-source
          - name: tekton-project-source
            resource: tekton-pipeline-source
  params:
    - name: package
      default: github.com/tektoncd/pipeline
    - name: resources
      default: conditions pipelineresources tasks pipelines taskruns pipelineruns
    - name: container-registry
      default: '141.125.106.77:32324'
    - name: kubeconfig-secret
      default: ppc64le-kubeconfig
    - name: target-arch
      default: ppc64le
  resources:
    - name: tekton-pipeline-source
      type: git
    - name: plumbing-source
      type: git
```

Apply all resoures, tasks & pipeline using `kubectl create` command

### Run the pipeline

Before running the pipeline, make sure docker registry is configured and `ppc64le-kubeconfig` secret exist which contains kubeconfig of the remote cluster.

```bash
kubectl get secret/ppc64le-kubeconfig

# if not found, create one
# here config is the kubeconfig file of remote cluster
kubectl create secret generic ppc64le-kubeconfig --from-file=config=config
```

### TODO

- [ ] Create cronjobs to run pipeline automatically.
- [ ] Explore on service account requirements.
- [ ] Configurations for remote cluster where e2e tests will run.

### References

- https://github.com/tektoncd/plumbing/blob/master/docs/dogfooding.md
- https://github.com/tektoncd/plumbing/tree/master/tekton
- https://kubectl.docs.kubernetes.io/installation/kustomize/binaries/
- https://github.com/tektoncd/plumbing/blob/master/hack/tekton_in_kind.sh
- https://github.com/tektoncd/plumbing/pull/663/files
- https://github.com/tektoncd/pipeline/blob/master/docs/pipelines.md#adding-finally-to-the-pipeline
