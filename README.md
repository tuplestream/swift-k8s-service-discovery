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

#### Integrating in your code



#### Discovering services in a local environment


