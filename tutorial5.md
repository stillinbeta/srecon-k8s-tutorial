# Tutorial 5 (controller-manager)

[`kube-controller-manager`][cm] is responsible for synchronizing state between api server and the real world.
The API server is responsible for recording the desired state of the cluster, then the controller manager is responsible for realizing it.

As the name suggests, the controller manager is not just one application.
Rather, it's a single binary with a number of different components built into it.

The [`kube-controller-manager` documentation][cmcli] lists the following controller managers:

* `attachdetach`
* `bootstrapsigner`
* `clusterrole-aggregation`
* `cronjob`
* `csrapproving`
* `csrcleaner`
* `csrsigning`
* `daemonset`
* `deployment`
* `disruption`
* `endpoint`
* `garbagecollector`
* `horizontalpodautoscaling`
* `job`
* `namespace`
* `nodeipam`
* `nodelifecycle`
* `persistentvolume-binder`
* `persistentvolume-expander`
* `podgc`
* `pv-protection`
* `pvc-protection`
* `replicaset`
* `replicationcontroller`
* `resourcequota`
* `root-ca-cert-publisher`
* `route`
* `service`
* `serviceaccount`
* `serviceaccount-token`
* `statefulset`
* `tokencleaner`
* `ttl`
* `ttl-after-finished`

We can't go through all of these, so we'll just concentrate on a few.

[cm]: https://kubernetes.io/docs/concepts/overview/components/#kube-controller-manager
[cmcli]: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/

## Credentials

`kube-controller-manager` accesses the API server.
Like [all other API clients][apiauth], we'll generate a `kubeconfig` so the controller-manager can access the API server.

[apiauth]: tutorial4.md#connecting-to-the-api-server

```yaml
$ sudo kubeadm init phase kubeconfig controller-manager
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
```

This will be written to `/etc/kubernetes/controller-manager.conf`

## The `kube-controller-manager` pod

Just like before, we'll start out with a pod skeleton.
The kubeadm command to generate a fully-generated manifest is `sudo kubeadm init phase control-plane controller-manager`, but we'll be creating this file from scratch.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-controller-manager:v1.13.4
    name: kube-controller-manager
```

## Networking

In this case, `hostNetwork` is less about serving and more about access.
If we didn't give the controller-manager `hostNetwork`, it would be segregated away from  our api server.
Normally Kubernetes would use a [Software-defined networking][network] to allow pods to access each other.
But in this case, because we are using static pods that are required for Kubernetes to function, we rely on host networking.

[network]: https://kubernetes.io/docs/concepts/cluster-administration/networking/

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-controller-manager:v1.13.4
    name: kube-controller-manager
  hostNetwork: true
```

## Volumes

### Certificate directory

We'll need the kubernetes `pki` directory.
For one, we'll need to specify the CA to use to validate our connection to the kubernetes API.
But we also need access to the Certificate Authority's private key, because some of the controllers are responsible for issuing certificates requesting through the API.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-controller-manager:v1.13.4
    name: kube-controller-manager
    volumeMounts:
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
```

### Controller credentials

The pod will need access to the credentials we issued for it.
Rather than mounting the entire `/etc/kubernetes` directory, which contains a number of sensitive files, we'll use the `FileOrCreate` type to just mount the supplied file.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-controller-manager:v1.13.4
    name: kube-controller-manager
    volumeMounts:
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
    - mountPath: /etc/kubernetes/controller-manager.conf
      name: kubeconfig
      readOnly: true
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
  - hostPath:
      path: /etc/kubernetes/controller-manager.conf
      type: FileOrCreate
    name: kubeconfig
```

## controller-manager arguments

It wouldn't be a Kubernetes component without a [long list of command line arguments][compcli].
There's [an ongoing effort][componentconfig] to move this type of configuration into configuration files, like we used to configure the kubelet.
But for now, we'll make another argument list.

[compcli]: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/#options
[componentconfig]: https://github.com/kubernetes/enhancements/blob/master/keps/sig-cluster-lifecycle/0032-create-a-k8s-io-component-repo.md#part-1-componentconfig

```yaml
    command:
    - kube-controller-manager
```

### Controller Credentials

We have both `authentication` and `authorization` arguments.
Both of these are optional, with functionality degrading with each not supplied.

Since our `kubeconfig` is administrator-level, we can use it for both, along with the vanilla `--kubeconfig`:

```yaml
    command:
    - kube-controller-manager
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
```

### CA files

Since we may need to validate client certificates that have been passed through to us, we need to know which CA to use for that:

```yaml
    command:
    - kube-controller-manager
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
```

### Issuing Cluster-wide certificates

The `csrsigning` controller needs credentials to sign with.
We'll use the same credentials that we use to validate the API server with:

```yaml
    command:
    - kube-controller-manager
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt
    - --cluster-signing-key-file=/etc/kubernetes/pki/ca.key
```

### Controllers

The `--controllers` flag specifies which of the many controllers to actually enable.
Kubeadm enables all of them by default, and that's what you'd likely do in production.
Instead, we will enable the bare minimum needed to get the cluster running.

* `bootstrapsigner` is a controller that signs a ConfigMap with a set of tokens.
  This is part of the the process of adding new nodes.
* `csrapproving` approves certificates requested [via the Kubernetes api][certapi].
* `csrsigning` actually signs certificates approved by `csrapproving`.
* `daemonset` is responsible for synchronizing [`DaemonSet` objects][daemonset] stored in the system with actual running pods.
* `deployment` is is responsible for synchronizing [Deployment][deployment] objects stored in the system with actual running replica sets and pods.
* `disruption` controls how much [disruption] can be applied to a pod.
* `endpoint` [joins services to pods][endpoints].
* `job` handles scheduling and cleaning up [jobs].
* `namespace` performs actions during [namespace phases][namespace-phases].
* `nodeipam` handles [IP Address Management][ipam] for Kubernetes.
* `nodelifecycle` handles [node] lifecycle events such as applying taints
* `podgc` cleans up unneeded pods.
* `replicaset` is responsible for synchronizing [`ReplicaSet`][replicasets] objects stored in the system with actual running pods.
* `tokencleaner` deletes expired [tokens].

[certapi]: https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/#create-a-certificate-signing-request-object-to-send-to-the-kubernetes-api
[daemonset]: https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/
[deployment]: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
[disruption]: https://github.com/kubernetes/kubernetes/issues/12611
[endpoints]: https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.12/#endpoints-v1-core
[jobs]: https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/
[namespace-phases]: https://github.com/kubernetes/community/blob/master/contributors/design-proposals/architecture/namespaces.md#phases
[ipam]: https://www.projectcalico.org/calico-ipam-explained-and-enhanced/
[node]: https://kubernetes.io/docs/concepts/architecture/nodes/
[replicasets]: https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/
[tokens]: https://kubernetes.io/docs/reference/access-authn-authz/bootstrap-tokens/

```yaml
    command:
    - kube-controller-manager
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --controllers=bootstrapsigner,csrapproving,csrsigning,daemonset,deployment,disruption,endpoints,job,namesapec,nodeipam,nodelifecycle,podgc,replicaset,tokencleaner
```

## Installing the Pod

Let's assemble our finished yaml:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-controller-manager
    tier: control-plane
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-controller-manager:v1.13.4
    command:
    - kube-controller-manager
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --controllers=bootstrapsigner,csrapproving,csrsigning,daemonset,deployment,disruption,endpoint,job,namespace,nodeipam,nodelifecycle,podgc,replicaset,tokencleaner
    name: kube-controller-manager
    volumeMounts:
    - mountPath: /etc/kubernetes/pki
      name: k8s-certs
      readOnly: true
    - mountPath: /etc/kubernetes/controller-manager.conf
      name: kubeconfig
      readOnly: true
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/pki
      type: DirectoryOrCreate
    name: k8s-certs
  - hostPath:
      path: /etc/kubernetes/controller-manager.conf
      type: FileOrCreate
    name: kubeconfig
```

Write this file out to `/etc/kubernetes/manifests/kube-controller-manager.yaml`

## Check status

```console
$ kubectl get pods --namespace kube-system
NAME                                   READY   STATUS    RESTARTS   AGE
etcd-k8s-tutorial                      1/1     Running   0          4h49m
kube-apiserver-k8s-tutorial            1/1     Running   0          4h49m
kube-controller-manager-k8s-tutorial   1/1     Running   0          2m33s
```

If your `kube-controller-manager` container isn't dying immediately, congratulations, you've configured it correctly! Next, we'll get the scheduler working, at which point we'll have a mostly-functional Kubernetes cluster.
