# SADIS Server for BBSIM
This repository builds a container that can be used to service SADIS
nd Bandwidth Profiles for all instances of BBSIM running in a
Kubernetes cluster.

## Overview
The container uses `kubectl` to discover all the services in the
kubernetes cluster that represent an BBSIM OLT. This is accomplished
by doing query over all namespaces for services with the label `bbsim`.

Once the list of BBSIM instances are discovered, each is queried via
REST (`curl`) to retrieve the instances SADIS and Bandwidth Profiles
configuration.

The configuration are combined and a file is created for each record,
either in `/data/subscribers` for SADIS entries or `/data/profiles`
for Bandwidth Profiles.

In the background a python3 based simple http server is started on
port `8080` that then servers the contents of the created files
as `JSON` over `HTTP`.

The container periodically (5s) will requery the BBSIM instances and
their SADIS and Bandwidth Profiles. The files in `/data` will then
be updated or deleted based on the currently discovered entries.

## Configuration
The important configuration aspect of this container is the credentials
required for the `kubectl` to access the Kubernetes information. This
is accomplished using a Kubernetes configuration map (`configmap`).

The `configmap` can be created from an existing `kubectl` configuration
file using the following command:
```
kubectl create configmap kube-config --from-file=$KUBECONFIG
```
This command creates a `configmap` named `kube-config` from the
existing configuration file specified by the environment variable
`$KUBECONFIG`.

This `configmap` is used when deploying the container as described in
the following section.

## Deployment
Included in this repository is a sample Kubernetes manifest file to
deploy the container named `bbsim-sadis-server.yaml`. This manifest
creates a Kubernetes service `bbsim-sadis-server` that is provided
by a pod using the same name. The pod uses a `volumeMount` to expose
the created `configmap` as the file `/etc/kube/kube_config` in the
container. Using the authentication keys from this file along with
the Kubernetes defined environment variables `$KUBERNETES_SERVICE_HOST`
and `$KUBERNETES_PORT_443_TCP_PORT` to the container is allowed
to connect to the Kubernetes API server via `kubectl`.

To create the container you can use the following command:
```
kubectl create -f bbsim-sadis-server.yaml
```

## ONOS Integration using kind-voltha
In order to use the BBSIM SADIS and Bandwidth Profile container
ONOS needs to be configured with the proper URLs with which to
contact the server. This is done via ONOS network configuration.

When using `kind-voltha` this can be used by setting the following
environment variables:
```
CONFIG_SADIS=url
SADIS_BANDWIDTH_PROFILES="http://bbsim-sadis-server.default.svc:58080/profiles/%s"
SADIS_SUBSCRIBERS="http://bbsim-sadis-server.default.svc:58080/subscribers/%s"
```
