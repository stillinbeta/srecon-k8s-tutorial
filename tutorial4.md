# Tutorial 4: Getting the API server running

The API server is the brain of Kubernetes.
It's the only component that communicates directly with `etcd`,
and usually the only publicly accessible control-plane component.
All Kubernetes clients interact pretty much exclusively with the API server, including proxy ports with `kubectl port-forward` and running tasks with `kubectl exec`.

By the end of this tutorial, your API server will be stood up and this server is going to look a lot more like a Kubernetes master node.

## Certificates

We're going to create a couple more certificates.
Luckily, we can use kubeadm for it.

### Certificate Authority

The API server uses a separate CA from etcd.
If it didn't, any valid client credentials could potentially connect directly to etcd,  bypassing all the access controls on the API server.

Let's generate that authority.

```console
$ sudo kubeadm init phase certs ca
[certs] Generating "ca" certificate and key
$ openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -text
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 0 (0x0)
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN = kubernetes
        Validity
            Not Before: Mar 24 18:32:57 2019 GMT
            Not After : Mar 21 18:32:57 2029 GMT
        Subject: CN = kubernetes
<snip>
```

### Server certificate

The API server will serve over https, and it needs a certificate to do that.

```console
$ sudo kubeadm init phase certs apiserver
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [k8s-tutorial kubernetes kubernetes.def
ault kubernetes.default.svc kubernetes.default.svc.cluster.local] and IPs [10.96.0.1 10.0.2.15
]
$ openssl verify -CAfile /etc/kubernetes/pki/ca.crt  /etc//kubernetes/pki/apiserver.crt
/etc//kubernetes/pki/apiserver.crt: OK
```

_NOTE: the IP addresses and names depend on your environment and hostname._

### API Server etcd client

API Server needs to talk to etcd as well, so we'll generate credentials that are valid with etcd.

```console
$ sudo kubeadm init phase certs apiserver-etcd-client
[certs] Generating "apiserver-etcd-client" certificate and key
$ openssl verify -CAfile /etc/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/apiserver-etcd-client.crt
/etc/kubernetes/pki/apiserver-etcd-client.crt: OK
```

Note that these credentials are issues by the `etcd` Certificate Authority, not APIServer's:

````console
$ openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apis
erver-etcd-client.crt
O = system:masters, CN = kube-apiserver-etcd-client
error 20 at 0 depth lookup: unable to get local issuer certificate
error /etc/kubernetes/pki/apiserver-etcd-client.crt: verification failed
```

## YAML manifest

As with `etcd`, we can have kubeadm generate our manifest.
That command is `sudo kubeadm init phase control-plane apiserver`.
But instead, we're going to make our own.
This will go in `/etc/kubernetes/manifests/` along with our sample pod.

Lets start out with some tags and our base image

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-apiserver:v1.13.4
    name: kube-apiserver
```

### Host Network

Like etcd, this pod will need access to the host network:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-apiserver:v1.13.4
    name: kube-apiserver
  hostNetwork: true
```

### Volumes

Like with `etcd`, we'll need to add the certificates we generated.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-apiserver:v1.13.4
    name: kube-apiserver
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

### Command

Now we need to construct our command.
Just like etcd, [there's a lot of options][kube-apiserver] so we're going to be making a long list.

[kube-apiserver]: https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/#options

```yaml
    command:
    - kube-apiserver
```

We'll start with certificates. We'll need the certificate authorities:

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
```

#### etcd

Add the etcd credentials:

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
```

The etcd server is at localhost:

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
```

#### HTTP Server

Add the server certificate and keys:

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
```

Enable https on port [`6443`][port6443]:

[port6443]: https://kubernetes.io/docs/reference/access-authn-authz/controlling-access/#api-server-ports-and-ips

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    - --secure-port=6443
```

And disable http:

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    - --secure-port=6443
    - --insecure-port=0
```

#### Authentication

We are going to be using client certificate authentication.
To enable this, we need to pass in the CA to validate certificates against:

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    - --secure-port=6443
    - --insecure-port=0
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
```

#### Authorization

[Authorization for Kubernetes][auth] can be a complicated thing to manage.
We are going to use the defaults that `kubeadm` chooses, as they're reasonably secure, real-world defaults.

That means two modes, [Node] and [RBAC].
Node authorization is a special mode that allows kubelets to access information such as [secrets] based what pods are scheduled on them.
RBAC stands for [Role Based Authorization][RBAC], which is a system for granting permissions to individual users.
A thorough overview of RBAC in k8s could easily be its own tutorial: for now we just need to know that we'll be matching up clients with a role stored in the API.

[auth]: https://kubernetes.io/docs/reference/access-authn-authz/authorization/#authorization-modules
[node]: https://kubernetes.io/docs/reference/access-authn-authz/node/
[RBAC]: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
[secrets]: https://kubernetes.io/docs/concepts/configuration/secret/

```yaml
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    - --secure-port=6443
    - --insecure-port=0
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --authorization-mode=Node,RBAC
```

### Putting it all together

Add our commands to our pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-apiserver
    tier: control-plane
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/kube-apiserver:v1.13.4
    name: kube-apiserver
    command:
    - kube-apiserver
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
    - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
    - --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
    - --etcd-servers=https://127.0.0.1:2379
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    - --secure-port=6443
    - --insecure-port=0
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    - --authorization-mode=Node,RBAC
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

Save this file as `/etc/kubernetes/manifests/kube-apiserver.yaml`.

After a few seconds, you should see a new container running:

```console
$ sudo docker ps | grep api
8744e499b264        fc3801f0fc54           "kube-apiserver --cl…"   About a minute ago   Up About a minute                       k8s_kube-apiserver_kube-apiserver
-k8s-tutorial_kube-system_0e03e38505f7290852ed04a5db4b9d73_0
72d77b649ca3        k8s.gcr.io/pause:3.1   "/pause"                 About a minute ago   Up About a minute                       k8s_POD_kube-apiserver-k8s-tutorial_kube-system_0e03e38505f7290852ed04a5db4b9d73_0
```

## Connecting to the API Server

The standard way of connecting to a Kubernetes cluster is a YAML file called a `kubeconfig`.
This file contains any number of credentials (which can be passwords, client certificates, or cloud provider tokens),
as well as an address to connect to.

In our case, it'll be a local IP addresses and credentials signed by by the API server certificate authority.

We can get kubeadm to generate this:

```console
$ sudo kubeadm init phase kubeconfig admin
[kubeconfig] Writing "admin.conf" kubeconfig file
```

The file is generated as `/etc/kubernetes/admin.conf`, not readable by non-root users.
Let's move them somewhere more convenient:

```shell
mkdir ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(whoami) ~/.kube/config
```

### `kubectl`

If you haven't already, you should install [`kubectl`][kubectl].
`kubectl` is utility used to access, configure, and administer Kubernetes clusters.

[kubectl]: https://kubernetes.io/docs/reference/kubectl/overview/

You should be able to install it using `apt`:

```shell
sudo apt install kubectl
```

And now you should be able to query the API server:

```console
$ kubectl get cm --all-namespaces
NAMESPACE     NAME                                 DATA   AGE
kube-system   extension-apiserver-authentication   1      16m
```

## Reconnect kubelet

Right now, the `kubelet` isn't connected to the API server, so we won't be able to run any pods.
Let's fix that.

### Bootstrap credentials

During [Tutorial 1][tut1], we commented out the first line of the `kubeadm`-provided `kubelet`.
That line pertained to [bootstrap credentials][bootstrap], and before we can uncomment it we need to generate those.

[tut1]: tutorial1.md#your-first-config-file
[bootstrap]: https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet-tls-bootstrapping/

`kubeadm` can create a bootstrap kubeconfig:

```console
$ sudo kubeadm init phase kubeconfig kubelet
[kubeconfig] Writing "kubelet.conf" kubeconfig file
```

Now we can uncomment that file:

```shell
sudoedit /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

If you're curious, you can look at the contents of `/etc/kubernetes/kubelet.conf` now that it's created.
The referenced `bootstrap-kubelet.conf` is only necessary if the `kubelet.conf` is not already provided.
That's what we would use if we were making a worker node instead of a master node.

If all's well, you should now be able to see the pods the kubelet is running for you:

```shell
$ kubectl get pods --namespace kube-system
NAME                          READY   STATUS    RESTARTS   AGE
etcd-k8s-tutorial             1/1     Running   0          2m10s
kube-apiserver-k8s-tutorial   1/1     Running   0          2m10s
```

## Conclusion

Your API server is now running!
You're most of the way to a working Kubernetes cluster.
Next, we'll set up a few more services that Kubernetes requires to function properly.
