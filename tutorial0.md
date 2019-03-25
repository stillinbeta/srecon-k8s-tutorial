# Tutorial 0: Setup

## Virtual Machines

A few isolated parts of this tutorial assume you are using Virtualbox.
This is not required, however, that is what this tutorial was tested on.
Using another hypervisor, cloud instances, or bare metal will quite possibly work, but may also fail in byzantine ways.
When configuring VirtualBox or a cloud instance, set (or chose) a CPU count >= 2. This will save you headaches later.

### Some virtualbox Hints

If you do choose to use virtualbox, you may find it helpful to have SSH access to your machine.
To do this, you will need to attach an additional "Host"-type adapter to your machine.
The default NAT network interface will provide you with internet access, but not the ability to access your VM from your host machine.

If you have both interfaces installed when you install Ubuntu, both will connect when the machine is started.
Otherwise, `dhclient <interface-name>` should get you an IP address.
It will probably look like `192.168.56.10x`, where x is any digit greater than 0.

Once you start the SSH server, you should be able to ssh to `user@192.168.56.10x`.

## Operating System

This tutorial was tested using Ubuntu 18.04.2 Bionic Server Edition.
Kubernetes (and specifically Kubeadm) officially support [Ubuntu, Debian, CentOS, RHEL, and a few others][oses].
Ubuntu was chosen because it is common, popular, and what I was most familiar with while writing the tutorial.
Most if not all of these tutorials _should_ work on other distributions, but this has not been tested, and there may be corner cases that trip you up.
If you plan on following along with the tutorial at SRECon, I recommend using Ubuntu Bionic so the TAs and I will be most able to assist you.

[oses]: https://kubernetes.io/docs/setup/independent/install-kubeadm/#before-you-begin
