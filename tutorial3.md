# Tutorial 3: etcd

[etcd][etcd] is the database that backs kubernetes.
All objects written to the kubernetes API ultimately end up in etcd, so it's important to get it running properly.

kubeadm defaults to using a single etcd node, so that's what we'll do here.
In production, you can optionally [set up a high-availability cluster][haetcd] for kubernetes instead.

[etcd]: https://github.com/etcd-io/etcd
[haetcd]: https://kubernetes.io/docs/setup/independent/setup-ha-etcd-with-kubeadm/

## Certificates

etcd is secured by a series of certificates.
This may not matter when everything is running locally, but etcd communicates over container boundaries.

The hierarchy is a little complicated, but we just want to get etcd running right now.

First, we'll create the CA. All the certificates we issue will be issued by this CA.
There's a lot of ways to set up a CA, but it's boring and outside the scope of this tutorial.
Instead, we'll get kubeadm to do it for us.

```console
$ sudo kubeadm init phase certs etcd-ca
[certs] Generating "etcd/ca" certificate and key
```

We can see what we generated:

```console
$ openssl x509 -in /etc/kubernetes/pki/etcd/ca.crt -noout -text
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 0 (0x0)
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: CN = etcd-ca
        Validity
            Not Before: Mar 23 22:57:46 2019 GMT
            Not After : Mar 20 22:57:46 2029 GMT
        Subject: CN = etcd-ca
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                Public-Key: (2048 bit)
<snip>
```

Now, we'll generate the server certificate.

```console
$ sudo kubeadm init phase certs etcd-server
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [k8s-tutorial localhost] and IPs [10.
0.2.15 127.0.0.1 ::1]
```

This certificate should be signed by the CA:

```console
$ openssl verify -CAfile /etc/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/etcd/server.crt
/etc/kubernetes/pki/etcd/server.crt: OK
```

Success! That's all we need to get the server started. We'll generate more certificates later.

## Creating the etcd pod

We could just use the static pod manifest that kubeadm provides.
If you run `sudo kubeadm init phase etcd local`, you'll get a manifest generated.

But to learn how etcd works, we should make our own.
This will go where our previous pod did, in `/etc/kubernetes/manifests`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
    image: k8s.gcr.io/etcd:3.2.24
    imagePullPolicy: IfNotPresent
    name: etcd
```

This should look a little familiar: we've written a pod manifest before.
But we're going to to flesh this one out a little bit more.
Let's look at the [arguments etcd takes][manetcd].

[manetcd]: https://coreos.com/etcd/docs/latest/op-guide/configuration.html

## Connecting to the cluster

We need to be able to connect.
But wait, this is going to be running inside a container.
How do we expose it to the rest of the cluster?

Normally, we'd use a [service][k8sservice] to expose a pod to the rest of the cluster.
But while we're bootstrapping, we can't run services.

Instead, we'll cheat a little bit.
Take a look at the [pod specification][podspec].
There's a `hostNetwork` option that will let us expose our network a little more publicly.
Let's turn that on:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
    image: k8s.gcr.io/etcd:3.2.24
    name: etcd
  hostNetwork: true
```

[podspec]: https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.13/#podspec-v1-core
[k8sservice]: https://kubernetes.io/docs/concepts/services-networking/service/

## etcd volumes

Pods get destroyed.
Systems can be rebooted, docker can be restarted, new images can be applied.
By default, when a pod goes away, its entire filesystem is lost to the ether.
Obviously, that's not ideal for a database.

### Mount Database storage

In Kubernetes, when we need persistent storage, we use a [`Volume`][k8svolume].

Most of [the volume types][volumetypes] are cloud-related or k8s-specific.
But the [hostPath] should work. Let's add that one in.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
    image: k8s.gcr.io/etcd:3.2.24
    name: etcd
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

[`DirectoryOrCreate`][hostPath] does exactly what it sounds like.

[k8svolume]: https://kubernetes.io/docs/concepts/storage/volumes/
[volumetypes]: https://kubernetes.io/docs/concepts/storage/volumes/#types-of-volumes
[hostPath]: https://kubernetes.io/docs/concepts/storage/volumes/#hostpath

### Mount Certificates

We also need access to all those certificates we created.
Another `hostPath` will handle that:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
    image: k8s.gcr.io/etcd:3.2.24
    name: etcd
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
  - hostPath:
      path: /etc/kubernetes/pki/etcd
      type: Directory
    name: etcd-certs
```

### Mounting the volumes

Right now, we've specified volumes but we haven't actually used them anywhere. We'll need to explicitly mount them into our container.

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
    image: k8s.gcr.io/etcd:3.2.24
    name: etcd
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /etc/kubernetes/pki/etcd
      name: etcd-certs
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
  - hostPath:
      path: /etc/kubernetes/pki/etcd
      type: Directory
    name: etcd-certs
```

## etcd Arguments

We're going to need a bunch of arguments. let's make a list.

```yaml
    command:
    - etcd
```

Let's give our cluster a name:

```yaml
    command:
    - etcd
    - --name=k8s-demo
```

We'll need to install all our certificates too.
So we'll add the CA:

```yaml
    command:
    - etcd
    - --name=k8s-demo
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
```

And our server certificates:

```yaml
    command:
    - etcd
    - --name=k8s-demo
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
```

Turn on authentication:

```yaml
    command:
    - etcd
    - --name=k8s-demo
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --client-cert-auth=true
```

Serve on https, not http.

```yaml
    command:
    - etcd
    - --name=k8s-demo
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --client-cert-auth=true
    - --listen-client-urls=https://0.0.0.0:2379
```

We use port 2379 because that's [the official port allocated to etcd][2379], as well the default.

When we specify `listen-client-urls`, we have to specify [`advertise-client-urls`][etcd-advertise] as well:

[etcd-advertise]: https://coreos.com/etcd/docs/latest/v2/configuration.html#--advertise-client-urls
[2379]: https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml?search=2379

```yaml
    command:
    - etcd
    - --name=k8s-demo
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --client-cert-auth=true
    - --listen-client-urls=https://0.0.0.0:2379
    - --advertise-client-urls=https://localhost:2379
```

We set up a data directory, so we may as well use it:

```yaml
    command:
    - etcd
    - --name=k8s-demo
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --client-cert-auth=true
    - --listen-client-urls=https://0.0.0.0:2379
    - --advertise-client-urls=https://localhost:2379
    - --data-dir=/var/lib/etcd
```

## Putting it all together

Add our command to our container:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: etcd
    tier: control-plane
  name: etcd
  namespace: kube-system
spec:
  containers:
  - image: k8s.gcr.io/etcd:3.2.24
    name: etcd
    command:
    - etcd
    - --name=k8s-demo
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --client-cert-auth=true
    - --listen-client-urls=https://0.0.0.0:2379
    - --advertise-client-urls=https://localhost:2379
    - --data-dir=/var/lib/etcd
    volumeMounts:
    - mountPath: /var/lib/etcd
      name: etcd-data
    - mountPath: /etc/kubernetes/pki/etcd
      name: etcd-certs
  hostNetwork: true
  volumes:
  - hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
  - hostPath:
      path: /etc/kubernetes/pki/etcd
      type: Directory
    name: etcd-certs
```

Now let's write it out and have `kubelet pick it up`.
Save the above yaml in `/etc/kubernetes/manifests` just like our example pod.

And now it should be running! Let's see:

```console
$ sudo docker ps | grep etcd
4dd1037c5b3b        3cab8e1b9802           "etcd --name=k8s-dem…"   50 seconds ago      Up 49 seconds                           k8s_etcd_etcd-k8s-tutorial_kube-system_9b90156916d8b089087c0
c7aa8e7018d_0
8750c1757738        k8s.gcr.io/pause:3.1   "/pause"                 51 seconds ago      Up 49 seconds                           k8s_POD_etcd-k8s-tutorial_kube-system_9b90156916d8b089087c0c
7aa8e7018d_0
```

Awesome, it's running!

## Health Check

We can check if our etcd is healthy in the same way an external health checker would.
First, to connect, we'll need valid certificates, signed by the etcd CA.
kubeadm can do it for us:

```console
$ sudo kubeadm init phase certs etcd-healthcheck-client
[certs] Generating "etcd/healthcheck-client" certificate and key
```

Once again, we can make sure this is signed:

```console
$ openssl verify -CAfile /etc/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/etcd/healthcheck-client.crt
/etc/kubernetes/pki/etcd/healthcheck-client.crt: OK
```

Now we should be able to run a health check!
etcd exposes an https health check:

```console
$ sudo curl -i --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt --key /etc/kubernetes/pki/etcd/healthcheck-client.key https://localhost:2379/health
HTTP/2 200
content-type: text/plain; charset=utf-8
content-length: 18
date: Sun, 24 Mar 2019 00:57:44 GMT

{"health": "true"}
```

Success!
