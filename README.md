# app-maintenance-operator

[![CI](https://github.com/k8s-operators-devops/app-maintenance-operator/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/k8s-operators-devops/app-maintenance-operator/actions/workflows/ci.yml)
[![Lint](https://github.com/k8s-operators-devops/app-maintenance-operator/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/k8s-operators-devops/app-maintenance-operator/actions/workflows/lint.yml)
[![E2E Tests](https://github.com/k8s-operators-devops/app-maintenance-operator/actions/workflows/test-e2e.yml/badge.svg?branch=main)](https://github.com/k8s-operators-devops/app-maintenance-operator/actions/workflows/test-e2e.yml)
[![Go Report Card](https://goreportcard.com/badge/github.com/k8s-operators-devops/app-maintenance-operator)](https://goreportcard.com/report/github.com/k8s-operators-devops/app-maintenance-operator)
[![Latest Release](https://img.shields.io/github/v/release/k8s-operators-devops/app-maintenance-operator?include_prereleases)](https://github.com/k8s-operators-devops/app-maintenance-operator/releases)
[![License](https://img.shields.io/github/license/k8s-operators-devops/app-maintenance-operator)](LICENSE)

`app-maintenance-operator` gives platform and application teams a controlled way to put ALB-backed Kubernetes applications into maintenance mode without editing the original application Ingress.

It is focused on application traffic maintenance, not node maintenance. The operator creates a temporary, higher-priority ALB IngressGroup overlay that returns an HTTP 503 maintenance response while leaving the business-owned Ingress unchanged.

End users install and operate it with `kubectl` only. Go, Kubebuilder, controller-gen, Kustomize, and Make are maintainer tools, not runtime requirements.

The operator never mutates the original application Ingress during normal enable or disable. It creates a separate maintenance Ingress in the same ALB IngressGroup and gives it higher precedence with `alb.ingress.kubernetes.io/group.order: "-1000"`.

## Prerequisites

- Kubernetes v1.25 or newer.
- AWS Load Balancer Controller installed.
- An existing AWS Load Balancer Controller ALB IngressGroup.
- Existing application Ingresses in that group must use one of:
  - `spec.ingressClassName: alb`
  - `kubernetes.io/ingress.class: alb`
- Existing application Ingresses must define an ALB IngressGroup ID/name with `alb.ingress.kubernetes.io/group.name`.
- `kubectl` access to the target cluster.
- A `kubectl` client that is within one minor version of the cluster control plane.

Start in a non-production namespace first. IngressGroup is powerful: any user who can create or update Ingresses in the same ALB IngressGroup can affect routing for that group.

Verify the ALB IngressGroup name before enabling maintenance:

```bash
kubectl get ingress -n <application-namespace> \
  -o custom-columns=NAME:.metadata.name,GROUP:.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name,LISTEN_PORTS:.metadata.annotations.alb\.ingress\.kubernetes\.io/listen-ports
```

Use the value in the `GROUP` column as `spec.albGroupName`. Create the `Maintenance` resource in the same namespace as the IngressGroup member Ingresses so the operator can discover the group's listener ports.

Inspect one group member when you need the full annotation set:

```bash
kubectl describe ingress <ingress-name> -n <application-namespace>
```

Confirm the annotations include `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`.

For AWS Load Balancer Controller users, `spec.albGroupName` is the recommended targeting mode. The operator discovers existing Ingresses in the same namespace with that group name and applies the maintenance overlay to the listener ports used by that group, including HTTPS listeners declared through `alb.ingress.kubernetes.io/listen-ports`.

## Installation

Choose the install mode that matches your operating model:

- **Global scoped**: one platform-owned operator watches `Maintenance` resources across application namespaces.
- **Namespace scoped**: one operator instance watches only the namespace where it is installed.

### Global Scoped Install

Use the pinned release manifest when one operator should reconcile maintenance across namespaces:

```bash
kubectl apply -f https://raw.githubusercontent.com/k8s-operators-devops/app-maintenance-operator/v1.1.1/deploy/install.yaml
```

Review the manifest first if you are installing from a local checkout:

```bash
kubectl apply --dry-run=client --validate=false -f deploy/install.yaml
```

The global scoped manifest includes the namespace, CRD, service account, manager `ClusterRole` and `ClusterRoleBinding`, leader election RBAC, metrics service, and manager deployment. No webhook resources are included because this operator does not use webhooks.

### Namespace Scoped Install

Use the namespace-scoped profile when one operator instance should watch only its own namespace:

```bash
kubectl apply -k https://github.com/k8s-operators-devops/app-maintenance-operator/config/namespaced?ref=v1.1.1
```

This profile sets `WATCH_NAMESPACE` from the operator pod namespace and uses namespaced `Role` and `RoleBinding` resources for manager permissions. The `Maintenance` resource and generated maintenance Ingress must live in that same namespace.

CRDs remain cluster-scoped Kubernetes resources, so installing the API still requires cluster-level permission.

The controller image is published to GHCR and pinned in the release manifest:

```text
ghcr.io/k8s-operators-devops/app-maintenance-operator:v1.1.1
```

### Planned Helm Install UX

Helm chart packaging is planned, but this repository does not publish a Helm chart yet. The examples below document the intended chart interface so the future chart stays aligned with the current manifest behavior. Use the pinned `kubectl apply` and `kubectl apply -k` commands above for installs today.

Planned global scoped Helm install:

```bash
helm install app-maintenance-operator <chart> \
  --namespace alb-maintenance-operator \
  --create-namespace
```

Planned namespace scoped Helm install:

```bash
helm install app-maintenance-operator <chart> \
  --namespace <application-namespace> \
  --create-namespace \
  --set scope=namespaced
```

Planned global scoped Helm install with a scheduled `Maintenance` resource:

```bash
helm install app-maintenance-operator <chart> \
  --namespace alb-maintenance-operator \
  --create-namespace \
  --set maintenance.create=true \
  --set maintenance.name=<maintenance-name> \
  --set maintenance.namespace=<application-namespace> \
  --set maintenance.albGroupName=<alb-ingress-group-name> \
  --set maintenance.maintenanceMode=true \
  --set-string maintenance.schedule.start="<start-time-rfc3339>" \
  --set-string maintenance.schedule.end="<end-time-rfc3339>"
```

Planned namespace scoped Helm install with a scheduled `Maintenance` resource:

```bash
helm install app-maintenance-operator <chart> \
  --namespace <application-namespace> \
  --create-namespace \
  --set scope=namespaced \
  --set maintenance.create=true \
  --set maintenance.name=<maintenance-name> \
  --set maintenance.albGroupName=<alb-ingress-group-name> \
  --set maintenance.maintenanceMode=true \
  --set-string maintenance.schedule.start="<start-time-rfc3339>" \
  --set-string maintenance.schedule.end="<end-time-rfc3339>"
```

Set `maintenance.albGroupName` to the existing ALB IngressGroup name. Schedule values must be RFC3339 timestamps, using `YYYY-MM-DDTHH:MM:SSZ` for UTC or `YYYY-MM-DDTHH:MM:SS-04:00` with an explicit offset.

Do not put watch scope in the `Maintenance` spec. Watch scope is deployment and RBAC configuration; maintenance intent belongs in the `Maintenance` resource. See [Configuration](docs/configuration.md) for the security boundaries of namespace-scoped operation.

## Verify

```bash
kubectl get pods -n alb-maintenance-operator
kubectl get crd maintenances.k8smaintenance.io
kubectl get maintenance -A
```

For controller logs:

```bash
kubectl logs -n alb-maintenance-operator \
  deployment/alb-maintenance \
  -c manager
```

## Enable Maintenance

Edit `samples/maintenance-enable.yaml` before applying it:

- replace `<maintenance-name>` with the name for the `Maintenance` resource;
- replace `<application-namespace>` with the namespace where the ALB IngressGroup member Ingresses live;
- replace `<alb-ingress-group-name>` with the existing ALB IngressGroup name.

```bash
kubectl apply -f samples/maintenance-enable.yaml
```

Example:

```yaml
apiVersion: k8smaintenance.io/v1alpha1
kind: Maintenance
metadata:
  name: <maintenance-name>
  namespace: <application-namespace>
spec:
  albGroupName: <alb-ingress-group-name>
  maintenanceMode: true
  response:
    backend: fixed-response
    html: '<html><head><title>Scheduled Maintenance</title><style>body{margin:0;font-family:Arial,sans-serif;background:#f6f8fb;color:#172033;display:flex;align-items:center;justify-content:center;height:100vh}.box{max-width:560px;padding:32px;text-align:center}h1{font-size:28px;margin:0 0 12px}p{font-size:16px;line-height:1.5;color:#5d6678;margin:0 0 14px}.code{font-size:13px;color:#7a4b00}</style></head><body><div class="box"><h1>Scheduled Maintenance</h1><p>We are performing planned maintenance and will be back shortly.</p><p>Thank you for your patience.</p><p class="code">HTTP 503 Service Unavailable</p></div></body></html>'
```

## Check Status

```bash
kubectl get maintenance -n <application-namespace>

kubectl describe maintenance <maintenance-name> -n <application-namespace>

kubectl get ingress -n <application-namespace>

kubectl get configmap -n <application-namespace>
```

Confirm the ALB group exists in the maintenance namespace:

```bash
kubectl get ingress -n <application-namespace> \
  -o custom-columns=NAME:.metadata.name,GROUP:.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name,LISTEN_PORTS:.metadata.annotations.alb\.ingress\.kubernetes\.io/listen-ports
```

Confirm the generated maintenance Ingress:

- is separate from the original application Ingress;
- has `k8smaintenance.io/managed-by=alb-maintenance-operator`;
- has `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`;
- has `alb.ingress.kubernetes.io/group.order: "-1000"`;
- has `alb.ingress.kubernetes.io/listen-ports` matching the discovered listener ports for the ALB group;
- uses backend service `maintenance` with port name `use-annotation`;
- contains `alb.ingress.kubernetes.io/actions.maintenance`;
- does not modify the original Ingress labels, annotations, or spec.

Endpoint check:

```bash
curl -i https://your-hostname.example.com/
```

Expected during maintenance:

```text
HTTP/2 503
content-type: text/html
```

## Disable Maintenance

```bash
kubectl apply -f samples/maintenance-disable.yaml
```

Or patch the existing resource:

```bash
kubectl patch maintenance <maintenance-name> \
  -n <application-namespace> \
  --type merge \
  -p '{"spec":{"maintenanceMode":false}}'
```

The generated maintenance Ingress should be removed. Normal application routing resumes through the unchanged application Ingresses.

## Schedule Maintenance

Set `spec.maintenanceMode: true` and use `spec.schedule.start` and `spec.schedule.end` to let the controller enable and disable maintenance mode automatically. Timestamps must be RFC3339 values. Choose the timezone that matches your change window by using either `Z` for UTC or an explicit offset such as `-04:00` or `+05:30`.

```yaml
apiVersion: k8smaintenance.io/v1alpha1
kind: Maintenance
metadata:
  name: <maintenance-name>
  namespace: <application-namespace>
spec:
  albGroupName: <alb-ingress-group-name>
  maintenanceMode: true
  schedule:
    start: "2026-07-20T22:00:00Z"
    end: "2026-07-20T23:00:00Z"
  response:
    backend: fixed-response
    html: '<html><head><title>Scheduled Maintenance</title><style>body{margin:0;font-family:Arial,sans-serif;background:#f6f8fb;color:#172033;display:flex;align-items:center;justify-content:center;height:100vh}.box{max-width:560px;padding:32px;text-align:center}h1{font-size:28px;margin:0 0 12px}p{font-size:16px;line-height:1.5;color:#5d6678;margin:0 0 14px}.code{font-size:13px;color:#7a4b00}</style></head><body><div class="box"><h1>Scheduled Maintenance</h1><p>We are performing planned maintenance and will be back shortly.</p><p>Thank you for your patience.</p><p class="code">HTTP 503 Service Unavailable</p></div></body></html>'
```

Apply the scheduled sample:

```bash
kubectl apply -f samples/maintenance-scheduled.yaml
```

Behavior:

- before `start`, the resource stays `Pending` and the generated maintenance Ingress is absent;
- from `start` until `end`, maintenance mode is enabled;
- at or after `end`, maintenance mode is disabled and generated resources are removed;
- `spec.maintenanceMode: false` or an omitted `spec.maintenanceMode` disables maintenance and ignores the schedule.
- `end` must be after `start`; invalid windows are reported with `InvalidSchedule`.

Example with an explicit local timezone offset:

```yaml
schedule:
  start: "2026-07-20T18:00:00-04:00"
  end: "2026-07-20T19:00:00-04:00"
```

## Uninstall

```bash
kubectl delete -f deploy/install.yaml
```

## Troubleshooting

- `targetIngress or albGroupName is required`: set exactly one targeting mode.
- `set either targetIngress or albGroupName, not both`: choose group-based or legacy target-Ingress mode.
- `no existing Ingresses found for ALB group`: confirm at least one application Ingress in the same namespace has `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`.
- `TargetIngressNotFound`: in legacy `targetIngress` mode, confirm the `Maintenance` resource is in the same namespace as the target Ingress.
- `InvalidConfiguration` for missing group name: in legacy `targetIngress` mode, add `alb.ingress.kubernetes.io/group.name` to the target Ingress.
- Non-ALB target error: in legacy `targetIngress` mode, set `spec.ingressClassName: alb` or `kubernetes.io/ingress.class: alb`.
- No HTTP paths/default backend error: in legacy `targetIngress` mode, ensure the target Ingress has at least one HTTP path or a default backend.
- Body limit error: ALB fixed-response message bodies are limited to 1024 bytes.
- Generated Ingress does not take precedence: confirm both Ingresses are in the same ALB IngressGroup and the generated Ingress has `group.order: "-1000"`.

## Limitations

- Only AWS ALB fixed-response mode is currently supported.
- `nginx` and existing `service` response backends are not implemented.
- Fixed-response HTML must be 1024 bytes or smaller.
- In legacy `targetIngress` mode, the target Ingress must be in the same namespace as the `Maintenance` resource.

See [Roadmap](ROADMAP.md) for planned work, including central platform-team control across namespaces.

## Maintainers

Maintainer workflows use the standard Kubebuilder project layout:

```bash
make verify
make bundle
```

Release images are published by GitHub Actions to GHCR when a `v*` tag is pushed, or manually through the image publish workflow. The publish workflow enforces the release gate before pushing any image: the release tag must point to the current protected `main` commit, and the `Tests`, `Lint`, and `Build` checks must be successful for that exact commit.

Before cutting a release tag, update pinned release references in one shot:

```bash
make bump-release VERSION=v1.1.1
```

Review `CHANGELOG.md`, merge the release-prep commit through the protected `main` branch, wait for required checks to pass on `main`, then create the immutable tag from that validated commit.

Documentation:

- [Architecture](docs/architecture.md)
- [Configuration](docs/configuration.md)
- [Testing](docs/testing.md)
- [Pain-relief blog draft](docs/blog/aws-load-balancer-controller-maintenance-page.md)
- [GitOps examples](examples/gitops)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
