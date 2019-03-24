# Tutorial 1

## Add the apt repository

```shell
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo tee /etc/apt/sources.list.d/kubernetes.list <<EOF
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
```

_NOTE: This is `xenial` regardless of the version of Ubuntu you are using. I am testing this on Ubuntu Bionic (18.04.2)._

## Install docker

For historical reasons, the docker package is `docker.io`.

```shell
sudo apt install docker.io
```

## Install kubelet and kubeadm

```shell
sudo apt update
sudo apt install kubelet kubeadm
```

## Check kubelet status

```shell
sudo systemctl status kubelet
```

You'll notice that it's crash-looping.
That's because it's looking for configuration files that don't exist.

```console
$ sudo journalctl --lines 5 --unit kubelet
Mar 23 01:33:17 k8s-tutorial kubelet[9484]: F0323 01:33:17.000166    9484 server.go:189] failed to load Kubelet config file /var/lib/kubelet/config.yaml, error failed to read kubelet config file "/var/lib/kubelet/config.yaml", error: open /var/lib/kubelet/config.yaml: no such file or directory
```

Let's tell it not to do that. Take a look at the command line from `systemctl status`:

```console
Process: 4857 ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS (code=exited, status=255)
```

_NOTE: The number after Process is a PID and will be different for every user._

Where do those arguments come from? Right above, there's this line:

```console
Drop-In: /etc/systemd/system/kubelet.service.d
         └─10-kubeadm.conf
```

Let's see what's in there.

```console
$ sudo cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
```

Bingo. Let's make an empty config file for it (e.g. with `touch`).

```console
$ sudo journalctl --lines 5 --unit kubelet
-- Logs begin at Fri 2019-03-22 19:46:26 UTC, end at Sat 2019-03-23 01:38:40 UTC. --
Mar 23 01:38:34 k8s-tutorial systemd[1]: Stopped kubelet: The Kubernetes Node Agent.
Mar 23 01:38:34 k8s-tutorial systemd[1]: Started kubelet: The Kubernetes Node Agent.
Mar 23 01:38:34 k8s-tutorial kubelet[10468]: F0323 01:38:34.760309   10468 server.go:189] failed to load Kubelet config file /var/lib/kubelet/config.yaml, error kubelet config file "/var/lib/kubelet/config.yaml" was empty
Mar 23 01:38:34 k8s-tutorial systemd[1]: kubelet.service: Main process exited, code=exited, status=255/n/a
Mar 23 01:38:34 k8s-tutorial systemd[1]: kubelet.service: Failed with result 'exit-code'.
k8s@k8s-tutorial:~$
```

That wasn't good enough.
Time to learn how to write a kubernetes config file.

## Your first config file

All of kubernetes uses a pretty standard configuration file format.
Everything is written in YAML, and there are a few fields that are common.

Behind the scenes, these are implemented by the [`TypeMeta`][typemeta] struct.
We can see there's two fields, `APIVersion` and `Kind`.

What goes there? We've got a [helpful reference file][kubeletcfg].

[typemeta]: https://godoc.org/k8s.io/apimachinery/pkg/apis/meta/v1#TypeMeta
[kubeletcfg]: https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/

```yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
```

Most API versions in Kubernetes look like that: a string that looks like a domain name (known as a *Group*), and a Version.
The only exception is the `core` group, which includes things like pods.
It's written `v1`, no domain or slash required.

Let's write this to our file and see what happens.

```shell
sudoedit /var/lib/kubelet/config.yaml
```

Then check the logs:

```console
$ sudo journalctl --lines 5 --unit kubelet
-- Logs begin at Fri 2019-03-22 19:46:26 UTC, end at Sat 2019-03-23 01:47:30 UTC. --
Mar 23 01:47:27 k8s-tutorial kubelet[12011]: I0323 01:47:27.764787   12011 server.go:407] Version: v1.13.4
Mar 23 01:47:27 k8s-tutorial kubelet[12011]: I0323 01:47:27.767512   12011 plugins.go:103] No cloud provider specified.
Mar 23 01:47:27 k8s-tutorial kubelet[12011]: F0323 01:47:27.767706   12011 server.go:261] failed to run Kubelet: unable to load bootstrap kubeconfig: stat /etc/kubernetes/bootstrap-kubelet.conf: no such file or directory
Mar 23 01:47:27 k8s-tutorial systemd[1]: kubelet.service: Main process exited, code=exited, status=255/n/a
Mar 23 01:47:27 k8s-tutorial systemd[1]: kubelet.service: Failed with result 'exit-code'.
```

Great, a new error message! let's tackle this one.
Looking at the [kubelet docs][kubelet], we can see that `--bootstrap-kubeconfig` is used for a kubeconfig we'll use to retrieve our real kubeconfig.
Since we don't have a kubelet yet, we can just comment this out.

[kubelet]: https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/

```shell
sudoedit /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

Comment out the line that starts with `Environment="KUBELET_KUBECONFIG_ARGS=`:

```shell
# Environment="KUBELET_KUBECONFIG_ARGS=
```

Reload the `systemd` daemons, since you changed a configuration file:

```shell
sudo systemctl daemon-reload
```

## Disable authentication

We've got a new error to deal with:

```console
$ sudo journalctl --lines 5 --unit kubelet
-- Logs begin at Fri 2019-03-22 19:46:26 UTC, end at Sat 2019-03-23 02:22:43 UTC. --
Mar 23 02:22:39 k8s-tutorial kubelet[20264]: I0323 02:22:39.259702   20264 plugins.go:103] No cloud provider specified.
Mar 23 02:22:39 k8s-tutorial kubelet[20264]: W0323 02:22:39.259867   20264 server.go:552] standalone mode, no API client
Mar 23 02:22:39 k8s-tutorial kubelet[20264]: F0323 02:22:39.260025   20264 server.go:261] failed to run Kubelet: no client provided, cannot use webhook authentication
Mar 23 02:22:39 k8s-tutorial systemd[1]: kubelet.service: Main process exited, code=exited, status=255/n/a
Mar 23 02:22:39 k8s-tutorial systemd[1]: kubelet.service: Failed with result 'exit-code'.
```

We don't need authentication! Let's turn it off.
Peeking through the [kubelet configuration][kubeletdoc], we can see that there's an object that [controls authentication][kubeletauth]. This is the default:

[kubeletdoc]: https://godoc.org/k8s.io/kubelet/config/v1beta1#KubeletConfiguration
[kubeletauth]: https://godoc.org/k8s.io/kubelet/config/v1beta1#KubeletAuthentication

```yaml
  anonymous:
    enabled: false
  webhook:
    enabled: true
    cacheTTL: "2m"
```

Let's override that in the `/var/lib/kubelet/config.yaml` we made earlier:

```yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  webhook:
    enabled: false
  anonymous:
    enabled: true
authorization:
  mode: AlwaysAllow
```

authentication and authorization are different.
authentication answers "who are you," and authorization answers "are you allowed."
To get the server to work in standalone mode, we have to give answers to both those questions.

If all's gone well, you should see some log lines that look like this:

```console
$ sudo journalctl --lines 10 --unit kubelet
-- Logs begin at Fri 2019-03-22 19:46:26 UTC, end at Sat 2019-03-23 02:43:50 UTC. --
Mar 23 02:42:17 k8s-tutorial kubelet[24818]: I0323 02:42:17.374717   24818 kubelet_node_status.go:278] Setting node annotation to enable volume controller attach/detach
Mar 23 02:42:27 k8s-tutorial kubelet[24818]: I0323 02:42:27.388418   24818 kubelet_node_status.go:278] Setting node annotation to enable volume controller attach/detach
```

And a much healthier status:

```console
$ sudo systemctl status kubelet
● kubelet.service - kubelet: The Kubernetes Node Agent
   Loaded: loaded (/lib/systemd/system/kubelet.service; enabled; vendor preset: enabled)
  Drop-In: /etc/systemd/system/kubelet.service.d
           └─10-kubeadm.conf
   Active: active (running) since Sun 2019-03-24 00:27:44 UTC; 1min ago
<snip>
```

Success! But the obvious question is: what can we _do_ with our lonely kubelet?

## Running Static pods

We're going to need a payload.
This can be anything we want, but let's try [`simpleservice`][simpleservice].

First, we need to modify our kubelet manifest to run static pods:

```yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  webhook:
    enabled: false
  anonymous:
    enabled: true
authorization:
  mode: AlwaysAllow
staticPodPath: /etc/kubernetes/manifests/
```

And restart the process:

A container isn't enough to run this, so we'll need a pod spec as well.
The `pod` is something you may find yourself writing, and there's even an [API page][podapi]!

[simpleservice]: https://hub.docker.com/r/mhausenblas/simpleservice/
[podapi]: https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.10/#pod-v1-core

You should end up with something like this:

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
    image: mhausenblas/simpleservice:0.5.0
    ports:
    - containerPort: 8080
    env:
    - name: PORT0
      value: "8080"
```

Write that out to a file in the `staticPodPath`:

```console
sudo tee /etc/kubernetes/manifests/simpleservice.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: myapp-pod
  labels:
    app: myapp
spec:
  containers:
  - name: myapp-container
    image: mhausenblas/simpleservice:0.5.0
    ports:
    - containerPort: 8080
    env:
    - name: PORT0
      value: "8080"
EOF
```

Kubelet will look for that file and start the pod. You can see this in the output from docker:

```console
$ sudo docker ps
CONTAINER ID        IMAGE                       COMMAND                  CREATED             STATUS              PORTS               NAMES
f96c7c333214        mhausenblas/simpleservice   "python ./simpleserv…"   7 minutes ago       Up 7 minutes                            k8s_myapp-container_myapp-pod-k8s-tutorial_default_7a32a55f16cc86f3976f4b8e2ee88408_0
586a9baa3e2e        k8s.gcr.io/pause:3.1        "/pause"                 7 minutes ago       Up 7 minutes                            k8s_POD_myapp-pod-k8s-tutorial_default_7a32a55f16cc86f3976f4b8e2ee88408_0
```

The `pause` container [is always present in every pod][pause]. Your container may take a few seconds to download and spin up.

[pause]: https://www.ianlewis.org/en/almighty-pause-container

NOTE: Probably most of the hashes here will be different. But the important this is the `k8s_myapp-container_myapp-pod`, which means our pod is running!

You'll notice the ports aren't exposed. Never fear, we can still access our service! First, get a shell running on the docker container:

```console
$ sudo docker exec -it <container id> bash
#
```

where `<container id>` is in the `docker ps` output.

NOTE: the `#` means that this is a root shell.
Your prompt will be longer, probably something like `root@myapp-pod-k8s-tutorial:/usr/src/app#`.
This has been omitted for brevity.

next, retrieve the IP address:

```console
# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
7: eth0@if8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
```

NOTE: Your IP address may be different, but it should still be in the `172.0.0.0/8` subnet.

Now, log out of that machine:

```console
# exit
$
```

And you should be able to curl our endpoint!

```console
$ curl -i http://172.17.0.2:8080/endpoint0
HTTP/1.1 200 OK
Date: Sat, 23 Mar 2019 03:32:56 GMT
Content-Length: 72
Etag: "246ff893b8e03857ceb41ac80403c24d5e255452"
Content-Type: application/json
Server: TornadoServer/4.3

{"host": "172.17.0.2:8080", "version": "0.5.0", "result": "all is well"}
```

## Conclusion

You've got your very own kubelet running!
The kubelet is the workhorse of kubernetes: most other components are ultimately working to schedule pods on nodes.
In a real environment, the API and kubelet connect to each other to schedule pods on whatever node has free resources.
But we've got a kubelet going it alone, and still providing a useful service.
If you wanted to only have one or two pods, you could stop here and forego the rest of Kubernetes!
But you would probably be missing out.
