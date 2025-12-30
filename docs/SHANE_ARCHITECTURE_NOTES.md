This jupyterhub system is designed to be upgraded in place. Typical workflow is
as follows:

Try something new in cae-testing --> move up to cae-dev --> deploy to cae

In reality, you may spend more time in cae-dev than cae-testing; this is because
some features (e.g., for VS Code to work at all) require a more 'real'
environment that is served over https , which in turn requires setting DNS
records and certificates.

### cae-testing

This environment doesn't have real authentication-- any username or password
will grant you access. It also doesn't have any sort of persistent address; you
access it via the load balancer address, which you can get by running:

```
make status ENVIRONMENT=cae-testing
```

...for the above command to work,we are assuming that you have basic command line
tools installed (tufo, aws-cli, kubectl, etc), and that you are authenticated to
the appropriate ERA aws account; typically, this is how I tell a shell which
account to use:

```
set -x AWS_ACCESS_KEY_ID AKIA6OD4...    # Replace with yours
set -x AWS_SECRET_ACCESS_KEY 'z2d...'   # Replace with yours
set -x AWS_DEFAULT_REGION us-west-2     # Possibly redundant (in tofu template)
```

I use the `fish` shell; for bash or similar you'd use `export` instead of `set`.

You can verify that you're setup in the correct environment using:

```
aws sts get-caller-identity
```

### cae-dev

This environment should be as close to your production environment as possible--
it has real authentication via cognito, and will generally have a dns entry
provisioned to give it a persistent address. This is a hub that if your users
had the web address, they would be able to login. The main difference between
this 'dev' environment and the production 'cae' is that we don't mount user
directories. The reason we don't is so that we can destroy it on a whim.

When you do (re)create it, you'll need to to get the load balancer address using
the same `make status` command (for this environment) after the cluster has
spawned, and then can use that to update the DNS records.

## Working with testing and dev... and production

There are both general and environment specific tofu templates; when you makes
changes to a configuration file that lives under ./environments , you are
impacting only that environment. However, if you make a change to anything in
./modules , or to and of the \*.tf files in root directory (main.tf,
variables.tf, etc), then you are making a change to *ALL* of the environments.

The git repo is setup so that when you push, it will check for changes to the
environments. If there is a change to just, say, cae-dev, then that change will
be applied to just that environment. If there has been a change to a module file
or base file, then the git workflow will detect that *both* have changed, and
will apply the change to both. There's a reason for this-- you may make a change
to the general template files when working on testing, and we want to know if
that change breaks the development environment.

Note that the above **DOES NOT** apply to the production `cae` environment. The
cae environment will only be rebuilt when there has been a change to one of it's
specific environment files that has been pushed to main. The reason for this is
because we don't want to *break* your production environment when you make a
change in in testing/dev that involves updating the global templates. This means
that you are free to experiment without impacting your production system. This
also means that it is *your responsibility* to **verify** that the dev
environment mirrors the changes you want to push to `cae`, and that the
environment can successfully build and deploy prior to pushing those changes to
`cae`.

The build and deploy scripts are very robust, but they can run into issues,
which is why we separate `cae` from the other two environments. As an example,
it is possible that during an `apply` (i.e., the tofu command we use to push
changes to a live cluster), a node group will die and need to be recreated. When
this happens, it will happen gracefully-- the system will purge the old group
and start from scratch, making a new node group that is healthy. However,
gracefully does not mean without impact; restarting a node group might cause aws
to provision a new loadbalancer, which will require a DNS update. This means
that **any** change to the `cae` environment must be *supervised*. An update may
be 'successful', but still require updating DNS by hand to ensure that users can
still login! Note that the above scenario is very rare-- I've run apply on
running clusters dozens of times and had the cluster respawn exactly once while
building out this project... but that's still a ~5% rate, and you should confirm
that updates to the running system occur without changing any of the routing
information.

## Creating and destroying testing and dev

Creating and updating a cluster is the same operation-- both run `tofu apply`
under the hood. The tofu commands are wrapped in `make`, so we actually run
`make apply` instead; the makefile has additional error checking and helper
functions. These functions will do backend work for you on creating a new
environment-- i.e., checking for kms key, and creating one for you if one
doesn't exist.

To `make` a new testing or dev environment, you just make changes to the
configuration files, and push those changes. If you have made changes to just
one environment, only that environment will be built. If you've made changes to
a base file, or both testing and dev, both environments will be built.

Typically, you'll build these environments and then want to spin them down--
that is, delete them (or `destroy`, in terraform / tofu language). The destroy
command is meant to erase them completely; i.e., deletes all user data, all
clusters, and eks control planes. Destroy means zero cost, which removes all the
aws infrastructure. To do this, I recommend running the github action; there's a
`destroy` workflow that you have to manually trigger from the github website UI,
which will also require you to type the environment name to confirm the destroy
sequence.

*There is no destroy option for cae, your production system, in the github UI*.
This is to prevent someone from accidentally removing your production system.
Also, you *should* never need to destroy that system. Destroy means destroy--
and would also remove all your persistent user directories. So the expectation
is that `cae` is updated via `apply`, but is never removed.

## The exception to 'live' updates -- your docker image

There are three types of upgrades that you can execute:

  1. Kubernetes (these are rare)
  2. Hub and hub infrastructure
  3. Userspace (i.e., the python environment)

Kubernetes upgrades are for your cluster, and shouldn't be needed for at least
the next 2 year. Hub updates are typically applied to you node groups-- and
since the main and dask-worker node groups scale to zero, you can execute these
with no user impact (the update pods will just 'appear' on the next refresh).
The hub updates are also what you are generally doing when you run any sort of
`apply` command via updating the tofu templates.

The userspace is governed by you docker image, and is different. That separation I
mentioned where production is isolated from testing and dev **doesn't apply**
for updates made to docker image. We could make this separate as well if we
wanted to-- but docker image updates are the lowest risk for you, and also the
most frequent thing you'll be doing... so as currently configured, they apply to
all environments, including production.

There's two caveats to above-- first, you can break the production environment with a
misconfigured docker image. Second, there is a delay between when you update the
docker image, and when it becomes 'live' on the production environment. That
delay is why the production system references the most recent docker image; you
still need to test changes to it. Most issues for the image should be be simple
to fix, and since the docker file is under git version control, rollbacks are
also simple.  
