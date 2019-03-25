# Tutorial 6: scheduler

The scheduler is responsible for allocating pods to nodes.
We only have one node right now, but the scheduler can scale to hundreds or thousands of nodes.
It can handle arbitrary constraints (e.g. only schedule on GPU nodes, don't schedule in this region), quality of service, resource requirements, and many other things.
You can think of it as a special case of the controller-manager, but it's the basis on which most other kubernetes primitives (including most controllers) rely.

## Credentials

Like the `controller-manager`, the scheduler gets all its information through the API server.
We'll need to give it credentials:

```console
$ sudo kubeadm init phase kubeconfig scheduler
[kubeconfig] Writing "scheduler.conf" kubeconfig file
```

This is written out to `/etc/kubernetes/scheduler.conf`.

## scheduler pod

The scheduler will be the last static pod we set up, so once more with feeling.
The kubeadm cheat is `sudo kubeadm init phase control-plane scheduler`

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-scheduler:v1.13.4
    name: kube-scheduler
```

### `hostNetwork`

Just like the `controller-manager`, we need `hostNetwork` to access the API server.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-scheduler:v1.13.4
    name: kube-scheduler
  hostNetwork: true
```

### Volume mounts

We only need one mount this time: our credentials.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-scheduler:v1.13.4
    name: kube-scheduler
  hostNetwork: true
  volumeMounts:
    - mountPath: /etc/kubernetes/scheduler.conf
      name: kubeconfig
      readOnly: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/scheduler.conf
      type: FileOrCreate
    name: kubeconfig
```

### Arguments

Refreshingly, the scheduler requires only one argument.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-scheduler:v1.13.4
    name: kube-scheduler
    volumeMounts:
    - mountPath: /etc/kubernetes/scheduler.conf
      name: kubeconfig
      readOnly: true
    command:
    - kube-scheduler
    - --kubeconfig=/etc/kubernetes/scheduler.conf
  hostNetwork: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/scheduler.conf
      type: FileOrCreate
    name: kubeconfig
```

## Write the scheduler

Write the pod out to `/etc/kubernetes/manifests/scheduler.yaml`

If all's gone well, your pod should be running properly:

```console
$ kubectl get pods --namespace kube-system
NAME                                   READY   STATUS    RESTARTS   AGE
etcd-k8s-tutorial                      1/1     Running   0          5h39m
kube-apiserver-k8s-tutorial            1/1     Running   0          5h39m
kube-controller-manager-k8s-tutorial   1/1     Running   0          52m
kube-scheduler-k8s-tutorial            1/1     Running   0          47s
```

## Apply a pod

Now that we've got a scheduler, we've got everything that we need to run a pod!

Here's an example pod from [the kubernetes documentation][k8spod].
Save it as a file in your local directory, i.e. `example.yaml`.

[k8spod]: https://kubernetes.io/docs/concepts/workloads/pods/pod-overview/

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp-pod
  labels:
    app: myapp
spec:
  containers:
  - name: myapp-container
    image: busybox
    command: ['sh', '-c', 'echo Hello Kubernetes! && sleep 3600']
```

Now, we can use `kubectl` to apply it to our cluster:

```console
$ kubectl apply -f example.yaml
pod/myapp-pod created
```

Let's see how it's doing:

```console
$ kubectl get po
NAME                     READY   STATUS    RESTARTS   AGE
myapp-pod                1/1     Running   0          12h
myapp-pod-k8s-tutorial   1/1     Running   1          18h
```

Looks like it's working!

We can check the logs:

```console
$ kubectl logs myapp-pod
Hello Kubernetes!
```

## Conclusion

At this point we have a (minimally) viable kubernetes cluster!
We can connect to the API, start and stop pods, and view logs.

For a real production cluster, there are a number of additional steps.
We don't have DNS, or networking, and we have a number of components that won't scale past a single instance.

But I hope at this point you're empowered to see Kubernetes as more than a black box that commands go into and pods come out of.
And hopefully next time something goes wrong, you'll know where to start.
