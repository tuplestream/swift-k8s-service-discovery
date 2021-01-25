# Swift K8s Service Discovery

[![CircleCI](https://img.shields.io/circleci/build/github/tuplestream/swift-k8s-service-discovery)](https://app.circleci.com/pipelines/github/tuplestream/swift-k8s-service-discovery)
[![Gitter](https://badges.gitter.im/tuplestream/oss.svg)](https://gitter.im/tuplestream/oss?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

Discover pods of interest in a Kubernetes cluster as they become available. This library honors Apple's [Swift Service Discovery](https://github.com/apple/swift-service-discovery) API.

## Getting started

#### Adding the package

Swift K8s Service Discovery uses [SwiftPM](https://swift.org/package-manager/) as its build tool. Add the package in the usual way, first with a new `dependencies` clause:

```swift
dependencies: [
    .package(url: "https://github.com/tuplestream/swift-k8s-service-discovery.git", from: "0.10.0")
]
```
then add the `K8sServiceDiscovery` module to your target dependencies:

```swift
dependencies: [.product(name: "K8sServiceDiscovery", package: "swift-k8s-service-discovery")]
```

#### Configuring cluster permissions for your application

Assuming your Kubernetes cluster has RBAC enabled, you need to give your pods sufficient permissions to look for other pods. You'll probably want to create a separate `ServiceAccount`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-new-serviceaccount
```

Additionally you'll need a `Role` or  `ClusterRole` allowing read permissions for pod resources:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  # "namespace" omitted since ClusterRoles are not namespaced
  # use a 'Role' instead if pods to be discovered live in the same namespace
  name: discover-pods
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
```

...and a `ClusterRoleBinding` to tie them together:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: watch-for-pods
subjects:
- kind: ServiceAccount
  name: my-new-serviceaccount
roleRef:
  kind: ClusterRole
  name: discover-pods
  apiGroup: rbac.authorization.k8s.io
```

then in your `Deployment`, `DaemonSet` or other workload, specify the privileged service account. For example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: nginx
spec:
  selector:
    matchLabels:
      name: nginx
  template:
    metadata:
      labels:
        name: nginx
    spec:
      containers:
      - name: galaxy
        image: nginx
      serviceAccountName: my-new-serviceaccount
```

#### Integrating in your code

Import the module and create a `K8sServiceDiscovery` instance:

```swift
import K8sServiceDiscovery


// the default initializer options are for code running inside a pod.
// use K8sServiceDiscovery.init(config: ...) for other environments, e.g. local dev
// (see below)
let discovery = K8sServiceDiscovery()
```

Then look up or subscribe to new pod updates:

```swift
// look for pods labeled name=nginx in the namespace nginx
let target = K8sObject(labelSelector: ["name":"nginx"], namespace: "nginx")

// start a subscription. NOTE: this does not block the calling thread
let token = sd.subscribe(to: target) { result in
    // todo
    switch result {
    case .failure:
        // handle lookup error
    case .success(let instances):
        // do something with discovered pods
    }
} onComplete: { reason in
    // something on completion
}
```

Remember to shut down any service discovery instances before stopping the process, otherwise you'll get an HTTP client error:

```swift
discovery.shutdown()
```

If you need to box the serivce disovery object in `ServiceDiscoveryBox`, this package exposes a `shutdown()` function on `ServiceDiscoveryBox<K8sObject, K8sPod>`.

#### Discovering services in a local environment

This package supports pod discovery for local development in two ways:

1) Using `kubectl proxy` and overriding the API host:

```yaml
let config = K8sDiscoveryConfig(apiUrl: "http://localhost:8001")
let discovery = K8sServiceDiscovery(config: config)
```

2) Using a fixed list of hosts when no Kubernetes cluster is available to get a `ServiceDiscoveryBox<K8sObject, K8sPod>` instance:

```yaml
let hosts = ["some.host.name"]
let discovery = K8sServiceDiscovery.fromFixedHostList(target: target, hosts: hosts)
```
