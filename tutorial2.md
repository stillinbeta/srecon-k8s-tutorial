# Tutorial 2: kubeadm Preflight checks

Get cozy, because we're going to spend most of the rest of our tutorial working with kubeadm.

## Phases

```console
$ kubeadm init --help
Run this command in order to set up the Kubernetes master.

The "init" command executes the following phases:

preflight                  Run master pre-flight checks
kubelet-start              Writes kubelet settings and (re)starts the kubelet
certs                      Certificate generation
  /etcd-ca                   Generates the self-signed CA to provision identities for etcd
  /etcd-server               Generates the certificate for serving etcd
  /etcd-peer                 Generates the credentials for etcd nodes to communicate with each other
  /apiserver-etcd-client     Generates the client apiserver uses to access etcd
  /etcd-healthcheck-client   Generates the client certificate for liveness probes to healtcheck etcd
  /ca                        Generates the self-signed Kubernetes CA to provision identities for other Kubernetes components
  /apiserver                 Generates the certificate for serving the Kubernetes API
  /apiserver-kubelet-client  Generates the Client certificate for the API server to connect to kubelet
  /front-proxy-ca            Generates the self-signed CA to provision identities for front proxy
  /front-proxy-client        Generates the client for the front proxy
  /sa                        Generates a private key for signing service account tokens along with its public key
kubeconfig                 Generates all kubeconfig files necessary to establish the control plane and the admin kubeconfig file
  /admin                     Generates a kubeconfig file for the admin to use and for kubeadm itself
  /kubelet                   Generates a kubeconfig file for the kubelet to use *only* for cluster bootstrapping purposes
  /controller-manager        Generates a kubeconfig file for the controller manager to use
  /scheduler                 Generates a kubeconfig file for the scheduler to use
control-plane              Generates all static Pod manifest files necessary to establish the control plane
  /apiserver                 Generates the kube-apiserver static Pod manifest
  /controller-manager        Generates the kube-controller-manager static Pod manifest
  /scheduler                 Generates the kube-scheduler static Pod manifest
etcd                       Generates static Pod manifest file for local etcd.
  /local                     Generates the static Pod manifest file for a local, single-node local etcd instance.
upload-config              Uploads the kubeadm and kubelet configuration to a ConfigMap
  /kubeadm                   Uploads the kubeadm ClusterConfiguration to a ConfigMap
  /kubelet                   Uploads the kubelet component config to a ConfigMap
mark-control-plane         Mark a node as a control-plane
bootstrap-token            Generates bootstrap tokens used to join a node to a cluster
addon                      Installs required addons for passing Conformance tests
  /coredns                   Installs the CoreDNS addon to a Kubernetes cluster
  /kube-proxy                Installs the kube-proxy addon to a Kubernetes cluster


Usage:
  kubeadm init [flags]
  kubeadm init [command]

Available Commands:
  phase       use this command to invoke single phase of the init workflow


<snip>
```

For now, we're just going to run the preflight checks.

```shell
kubeadm init phase preflight
```

Depending on how you've set up your VM, you might see one of several errors.
Here's a breakdown.

### `IsPrivilegedUser`

Error: `[ERROR IsPrivilegedUser]: user is not running as root`

Fix: Run `kubeadm` with `sudo`

### `Swap`

Error: `[ERROR Swap]: running with swap on is not supported. Please disable swap`

Fix: `sudo swapoff -a`. You can also remove the swap mount from `/etc/fstab` for a more permanent solution

### `SystemVerification`

Error: `[WARNING SystemVerification]: this Docker version is not on the list of validated versions: 18.09.2. Latest validated version: 18.06`

Fix: You can downgrade Docker to a supported version.
List the available versions:

``` console
$ sudo apt-cache madison docker.io
 docker.io | 18.09.2-0ubuntu1~18.04.1 | http://archive.ubuntu.com/ubuntu bionic-updates/universe amd64 Packages
 docker.io | 18.06.1-0ubuntu1.2~18.04.1 | http://archive.ubuntu.com/ubuntu bionic-security/universe amd64 Packages
 docker.io | 17.12.1-0ubuntu1 | http://archive.ubuntu.com/ubuntu bionic/universe amd64 Packages
 ```

That second one is the one we want. You specify a version for `apt` using `=`:

```console
sudo apt install docker.io=18.06.1-0ubuntu1.2~18.04.1
```

If you have containers running already, a prompt will ask you if you want to restart the docker service (and therefore them). Do this, as the kubelet will handle restarting your containers.

### `NumCPU`

Error: `[ERROR NumCPU]: the number of available CPUs 1 is less than the required 2`

Fix: By default, Virtualbox gives VMs one CPU.
To mollify kubelet, we can increase this to two.

1. Shut down your VM. It needs to actually shut down, not just be paused.

   ```console
   sudo systemctl poweroff
   ```

2. go into the Virtualbox Manager window (i.e. the one that lists all your VMs.)
3. Select your k8s virtual machine, and click Settings.
4. Click the System option on the left.
5. Under the Processor tab, increase the slider to two.

That's it! Reboot your machine, and it should pass this preflight check now.

### `Service-Docker`

Error: `[WARNING Service-Docker]: docker service is not enabled, please run 'systemctl enable docker.service'`

Fix: As the message suggests, run `sudo systemctl enable docker.service`.

### `Port-10250`

Error: `[ERROR Port-10250]: Port 10250 is in use`

Fix: This port is in use by the kubelet. You can safely ignore it, or temporarily stop the service to mollify the preflight check: `sudo systemctl stop kubelet`

### Ignoring Errors

You can choose to ignore any of these errors with `--ignore-preflight-errors=<something`, where something is an identifier like `NumCPU` or `SystemVerification`.
Keep in mind that these guard rails are all here for a reason. If you choose to ignore errors, you may encounter even weirder errors down the road.

## Success(?)

You should have `sudo kubeadm init phase preflight` running without any errors.
