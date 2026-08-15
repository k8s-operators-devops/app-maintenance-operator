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

The operator never mutates the original application Ingress during normal enable or disable. It creates a separate maintenance Ingress in the same ALB IngressGroup and gives it higher precedence with `alb.ingress.kubernetes.io/group.order: "-1000"`. AWS Load Balancer Controller then reconciles that generated Ingress into a higher-priority ALB listener rule that serves the fixed maintenance response.

> **Purpose:** Route AWS ALB Ingress traffic to a maintenance response with a high-priority ALB listener rule while preserving existing application Ingress routing, redirects, and backend rules.

## Problem It Solves

Maintenance windows for ALB-backed Kubernetes applications are often handled by manually editing application Ingress objects, changing ALB listener rules in AWS, or adding temporary redirect/fixed-response actions under pressure. That creates operational risk:

- application-owned Ingress routing can be accidentally changed or overwritten;
- ALB redirect rules and backend rules can drift from the desired Kubernetes state;
- rollback depends on manual memory, screenshots, or out-of-band backups;
- scheduled windows are hard to express through GitOps or normal Kubernetes workflows;
- multiple application teams sharing one ALB IngressGroup can step on each other's routing changes.

`app-maintenance-operator` moves that workflow into a declarative Kubernetes API. Users create a `Maintenance` custom resource, and the controller reconciles a temporary overlay Ingress that AWS Load Balancer Controller converts into the maintenance listener rule.

## Why Kubernetes Native

- **Declarative operations:** maintenance intent is stored in a Kubernetes custom resource instead of an ad hoc console change.
- **Reconciliation:** the controller continuously drives the generated maintenance Ingress toward the requested state.
- **Separation of ownership:** application Ingresses remain owned by application teams; maintenance routing is owned by the operator.
- **GitOps alignment:** maintenance windows can be reviewed, applied, audited, and reverted through normal Kubernetes delivery workflows.
- **Scheduled automation:** `spec.schedule` defines the start and end of a maintenance window without a manual late-night toggle.
- **Safer rollback:** disabling maintenance removes the generated overlay and returns traffic to existing ALB listener rules.

## Prerequisites

- Kubernetes v1.25 or newer.
- AWS Load Balancer Controller installed.
- `kubectl` access to the target cluster.
- A `kubectl` client that is within one minor version of the cluster control plane.
- At least one existing ALB-backed application Ingress that is already working through AWS Load Balancer Controller.
- AWS Load Balancer Controller IAM permissions that allow ALB listener rule management.

Start in a non-production namespace first. IngressGroup is powerful: any user who can create or update Ingresses in the same ALB IngressGroup can affect routing for that group.

### AWS Load Balancer Controller IAM

The generated maintenance Ingress is reconciled by AWS Load Balancer Controller, so the required AWS IAM permissions must be attached to the AWS Load Balancer Controller role or service account. Do not attach AWS ALB permissions to the app-maintenance-operator service account; this operator creates Kubernetes resources, while AWS Load Balancer Controller creates and updates the ALB listener rules.

Use the official AWS Load Balancer Controller IAM policy for your controller version. At minimum, the controller role must be able to describe listeners/rules and create, modify, reprioritize, and delete listener rules for the managed ALB. For maintenance overlays, missing `elasticloadbalancing:SetRulePriorities` commonly shows up as an AWS Load Balancer Controller `FailedDeployModel` event.

Rule-management permissions needed by the AWS Load Balancer Controller include:

- `elasticloadbalancing:CreateRule`
- `elasticloadbalancing:DeleteRule`
- `elasticloadbalancing:ModifyRule`
- `elasticloadbalancing:SetRulePriorities`
- `elasticloadbalancing:DescribeRules`
- `elasticloadbalancing:DescribeListeners`

After IAM policy changes, the maintenance operator does not need to restart. AWS IAM permissions apply to the AWS Load Balancer Controller role. If AWS Load Balancer Controller continues to log `AccessDenied` after the role is updated, restart the AWS Load Balancer Controller deployment so it refreshes credentials:

```bash
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system
```

Restart the maintenance operator only when changing its deployment configuration, such as switching between cluster-scoped and namespace-scoped watch mode. Changing a `Maintenance` resource from `targetIngress` to `albGroupName`, or updating the `albGroupName` value, is reconciled automatically and does not require an operator restart.

The operator supports two targeting modes. Choose one per `Maintenance` resource.

| User preference | Use this field | Best fit |
| --- | --- | --- |
| "Put this whole ALB IngressGroup into maintenance." | `spec.albGroupName` | Recommended for AWS Load Balancer Controller users who know the shared IngressGroup name. |
| "Put the ALB group used by this specific Ingress into maintenance." | `spec.targetIngress` | Useful when application teams know their Ingress name but not the ALB group name. |

Do not set both fields in the same `Maintenance` resource.

### Prerequisites for `albGroupName`

Use `spec.albGroupName` when you want to target an existing AWS Load Balancer Controller IngressGroup directly.

Required:

- Application Ingresses must be in the same namespace as the `Maintenance` resource.
- At least one Ingress in that namespace must have:
  - `spec.ingressClassName: alb`, or
  - `kubernetes.io/ingress.class: alb`
- The Ingresses must define the ALB group annotation:
  - `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`
- If HTTPS or custom listeners are used, the existing group member Ingress should define:
  - `alb.ingress.kubernetes.io/listen-ports`

Verify the group name before enabling maintenance:

```bash
kubectl get ingress -n <application-namespace> \
  -o custom-columns=NAME:.metadata.name,GROUP:.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name,LISTEN_PORTS:.metadata.annotations.alb\.ingress\.kubernetes\.io/listen-ports
```

Use the value in the `GROUP` column as `spec.albGroupName`.

### Prerequisites for `targetIngress`

Use `spec.targetIngress` when you want to point at one existing ALB Ingress by name. The operator reads that Ingress for ALB metadata, discovers its group name and listener ports, and creates one separate high-priority catch-all maintenance Ingress for that ALB group.

Required:

- The target Ingress must be in the same namespace as the `Maintenance` resource.
- The target Ingress must be ALB-managed through:
  - `spec.ingressClassName: alb`, or
  - `kubernetes.io/ingress.class: alb`
- The target Ingress must define:
  - `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`
- If HTTPS or custom listeners are used, the target Ingress should define:
  - `alb.ingress.kubernetes.io/listen-ports`

Inspect one group member when you need the full annotation set:

```bash
kubectl describe ingress <ingress-name> -n <application-namespace>
```

Confirm the annotations include `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`.

For AWS Load Balancer Controller users, `spec.albGroupName` is the clearest platform-team interface. `spec.targetIngress` is also supported for teams that prefer to identify the application by Ingress name. Both modes leave the original application Ingress unchanged.

## Installation

Choose the install mode that matches your operating model:

- **Global scoped**: one platform-owned operator watches `Maintenance` resources across application namespaces.
- **Namespace scoped**: one operator instance watches only the namespace where it is installed.

### Global Scoped Install

Use the pinned release manifest when one operator should reconcile maintenance across namespaces:

```bash
kubectl apply -f https://raw.githubusercontent.com/k8s-operators-devops/app-maintenance-operator/v1.2.1/deploy/install.yaml
```

Review the manifest first if you are installing from a local checkout:

```bash
kubectl apply --dry-run=client --validate=false -f deploy/install.yaml
```

The global scoped manifest includes the namespace, CRD, service account, manager `ClusterRole` and `ClusterRoleBinding`, leader election RBAC, metrics service, and manager deployment. No webhook resources are included because this operator does not use webhooks.

### Namespace Scoped Install

Use the namespace-scoped profile when one operator instance should watch only its own namespace:

```bash
kubectl apply -k https://github.com/k8s-operators-devops/app-maintenance-operator/config/namespaced?ref=v1.2.1
```

This profile sets `WATCH_NAMESPACE` from the operator pod namespace and uses namespaced `Role` and `RoleBinding` resources for manager permissions. The `Maintenance` resource and generated maintenance Ingress must live in that same namespace.

CRDs remain cluster-scoped Kubernetes resources, so installing the API still requires cluster-level permission.

The controller image is published to GHCR and pinned in the release manifest:

```text
ghcr.io/k8s-operators-devops/app-maintenance-operator:v1.2.1
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
  --set-string maintenance.schedule.start="<YYYY-MM-DDTHH:MM:SSZ-or-offset>" \
  --set-string maintenance.schedule.end="<YYYY-MM-DDTHH:MM:SSZ-or-offset>"
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
  --set-string maintenance.schedule.start="<YYYY-MM-DDTHH:MM:SSZ-or-offset>" \
  --set-string maintenance.schedule.end="<YYYY-MM-DDTHH:MM:SSZ-or-offset>"
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

## Create Maintenance

Create one `Maintenance` resource in the application namespace. Pick exactly one targeting mode:

- `albGroupName`: target an existing AWS Load Balancer Controller IngressGroup by group name.
- `targetIngress`: target one existing ALB Ingress by name; the operator reads its ALB group and listener metadata.

Both modes create a separate maintenance Ingress with one high-priority catch-all `/*` rule. AWS Load Balancer Controller turns that generated Ingress into an ALB listener rule for the same IngressGroup. The original application Ingress is not modified.

> **Operational model:** The operator changes maintenance routing by creating a managed overlay Ingress. It does not rewrite existing application paths, redirect actions, or backend service rules.

### Option A: ALB IngressGroup Name

Use this when you know the ALB group name and want the clearest AWS Load Balancer Controller workflow.

Required before applying:

- Replace `<maintenance-name>` with a name for this maintenance window.
- Replace `<application-namespace>` with the namespace that contains the ALB group member Ingresses.
- Replace `<alb-ingress-group-name>` with the value from `alb.ingress.kubernetes.io/group.name`.

Enable maintenance immediately:

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

Equivalent sample file:

```bash
kubectl apply -f samples/maintenance-enable.yaml
```

Schedule maintenance for an ALB IngressGroup:

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
    # RFC3339 format. Examples: 2026-09-01T22:00:00Z or 2026-09-01T18:00:00-04:00.
    start: "<YYYY-MM-DDTHH:MM:SSZ-or-offset>"
    end: "<YYYY-MM-DDTHH:MM:SSZ-or-offset>"
  response:
    backend: fixed-response
    html: '<html><head><title>Scheduled Maintenance</title><style>body{margin:0;font-family:Arial,sans-serif;background:#f6f8fb;color:#172033;display:flex;align-items:center;justify-content:center;height:100vh}.box{max-width:560px;padding:32px;text-align:center}h1{font-size:28px;margin:0 0 12px}p{font-size:16px;line-height:1.5;color:#5d6678;margin:0 0 14px}.code{font-size:13px;color:#7a4b00}</style></head><body><div class="box"><h1>Scheduled Maintenance</h1><p>We are performing planned maintenance and will be back shortly.</p><p>Thank you for your patience.</p><p class="code">HTTP 503 Service Unavailable</p></div></body></html>'
```

Equivalent sample file:

```bash
kubectl apply -f samples/maintenance-scheduled.yaml
```

### Option B: Target Ingress Name

Use this when the application team knows the Ingress name and wants the operator to derive the ALB group from that Ingress.

Required before applying:

- Replace `<maintenance-name>` with a name for this maintenance window.
- Replace `<application-namespace>` with the namespace that contains the target Ingress.
- Replace `<target-ingress-name>` with the existing ALB Ingress name.
- Confirm the target Ingress has `alb.ingress.kubernetes.io/group.name`.

Enable maintenance immediately:

```yaml
apiVersion: k8smaintenance.io/v1alpha1
kind: Maintenance
metadata:
  name: <maintenance-name>
  namespace: <application-namespace>
spec:
  targetIngress: <target-ingress-name>
  maintenanceMode: true
  response:
    backend: fixed-response
    html: '<html><head><title>Scheduled Maintenance</title><style>body{margin:0;font-family:Arial,sans-serif;background:#f6f8fb;color:#172033;display:flex;align-items:center;justify-content:center;height:100vh}.box{max-width:560px;padding:32px;text-align:center}h1{font-size:28px;margin:0 0 12px}p{font-size:16px;line-height:1.5;color:#5d6678;margin:0 0 14px}.code{font-size:13px;color:#7a4b00}</style></head><body><div class="box"><h1>Scheduled Maintenance</h1><p>We are performing planned maintenance and will be back shortly.</p><p>Thank you for your patience.</p><p class="code">HTTP 503 Service Unavailable</p></div></body></html>'
```

Equivalent sample file:

```bash
kubectl apply -f samples/maintenance-enable-ingress.yaml
```

Schedule maintenance for a target Ingress:

```yaml
apiVersion: k8smaintenance.io/v1alpha1
kind: Maintenance
metadata:
  name: <maintenance-name>
  namespace: <application-namespace>
spec:
  targetIngress: <target-ingress-name>
  maintenanceMode: true
  schedule:
    # RFC3339 format. Examples: 2026-09-01T22:00:00Z or 2026-09-01T18:00:00-04:00.
    start: "<YYYY-MM-DDTHH:MM:SSZ-or-offset>"
    end: "<YYYY-MM-DDTHH:MM:SSZ-or-offset>"
  response:
    backend: fixed-response
    html: '<html><head><title>Scheduled Maintenance</title><style>body{margin:0;font-family:Arial,sans-serif;background:#f6f8fb;color:#172033;display:flex;align-items:center;justify-content:center;height:100vh}.box{max-width:560px;padding:32px;text-align:center}h1{font-size:28px;margin:0 0 12px}p{font-size:16px;line-height:1.5;color:#5d6678;margin:0 0 14px}.code{font-size:13px;color:#7a4b00}</style></head><body><div class="box"><h1>Scheduled Maintenance</h1><p>We are performing planned maintenance and will be back shortly.</p><p>Thank you for your patience.</p><p class="code">HTTP 503 Service Unavailable</p></div></body></html>'
```

Equivalent sample file:

```bash
kubectl apply -f samples/maintenance-scheduled-ingress.yaml
```

### Schedule Behavior

Set `spec.maintenanceMode: true` and use `spec.schedule.start` and `spec.schedule.end` to let the controller enable and disable maintenance mode automatically. Timestamps must be RFC3339 values. Use `YYYY-MM-DDTHH:MM:SSZ` for UTC, or include an explicit offset such as `YYYY-MM-DDTHH:MM:SS-04:00`.

Behavior:

- before `start`, the resource stays `Pending` and the generated maintenance Ingress is absent;
- from `start` until `end`, maintenance mode is enabled;
- at or after `end`, maintenance mode is disabled and generated resources are removed;
- `spec.maintenanceMode: false` or an omitted `spec.maintenanceMode` disables maintenance and ignores the schedule;
- `end` must be after `start`; invalid windows are reported with `InvalidSchedule`.

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
- causes AWS Load Balancer Controller to create or update a higher-priority ALB listener rule for the maintenance fixed response;
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

For ALB IngressGroup targeting:

```bash
kubectl apply -f samples/maintenance-disable.yaml
```

For Ingress-name targeting:

```bash
kubectl apply -f samples/maintenance-disable-ingress.yaml
```

Or patch the existing resource:

```bash
kubectl patch maintenance <maintenance-name> \
  -n <application-namespace> \
  --type merge \
  -p '{"spec":{"maintenanceMode":false}}'
```

The generated maintenance Ingress should be removed. Normal application routing resumes through the unchanged application Ingresses.

## Uninstall

Delete `Maintenance` resources before removing the operator. This gives the controller a chance to run its finalizer cleanup, delete generated maintenance Ingresses, and remove backup ConfigMaps while the operator is still running.

For a global scoped install:

```bash
kubectl get maintenance -A
kubectl delete maintenance --all -A
kubectl get maintenance -A
kubectl delete -f https://raw.githubusercontent.com/k8s-operators-devops/app-maintenance-operator/v1.2.1/deploy/install.yaml
```

For a namespace scoped install, delete `Maintenance` resources from the namespace watched by that operator instance:

```bash
kubectl get maintenance -n <application-namespace>
kubectl delete maintenance --all -n <application-namespace>
kubectl get maintenance -n <application-namespace>
kubectl delete -k https://github.com/k8s-operators-devops/app-maintenance-operator/config/namespaced?ref=v1.2.1
```

Wait until `kubectl get maintenance` returns no resources before deleting the install manifest. If a `Maintenance` resource stays in `Terminating`, inspect the generated maintenance Ingress and operator logs before removing finalizers manually:

```bash
kubectl get ingress -n <application-namespace>
kubectl describe ingress -n <application-namespace> <generated-maintenance-ingress-name>
kubectl logs -n alb-maintenance-operator deploy/alb-maintenance
```

## Troubleshooting

- `targetIngress or albGroupName is required`: set exactly one targeting mode.
- `set either targetIngress or albGroupName, not both`: choose ALB IngressGroup targeting or Ingress-name targeting.
- `no existing Ingresses found for ALB group`: confirm at least one application Ingress in the same namespace has `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`.
- `TargetIngressNotFound`: with Ingress-name targeting, confirm the `Maintenance` resource is in the same namespace as the target Ingress.
- `InvalidConfiguration` for missing group name: with Ingress-name targeting, add `alb.ingress.kubernetes.io/group.name` to the target Ingress.
- Non-ALB target error: with Ingress-name targeting, set `spec.ingressClassName: alb` or `kubernetes.io/ingress.class: alb`.
- `FailedDeployModel` or `AccessDenied` from AWS Load Balancer Controller: confirm the AWS Load Balancer Controller IAM role includes ALB listener rule permissions, especially `elasticloadbalancing:SetRulePriorities`.
- Body limit error: ALB fixed-response message bodies are limited to 1024 bytes.
- Generated Ingress does not take precedence: confirm both Ingresses are in the same ALB IngressGroup and the generated Ingress has `group.order: "-1000"`.
- Generated Ingress exists but no ALB listener rule appears: inspect AWS Load Balancer Controller logs and events, then verify `CreateRule`, `ModifyRule`, `DeleteRule`, `DescribeRules`, `DescribeListeners`, and `SetRulePriorities` permissions on the controller IAM role.

Inspect AWS Load Balancer Controller events and logs:

```bash
kubectl describe ingress <generated-maintenance-ingress-name> -n <application-namespace>
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

Restart guidance:

- Updating `spec.albGroupName`, `spec.targetIngress`, `spec.maintenanceMode`, or `spec.schedule` does not require restarting the maintenance operator.
- Switching the operator deployment between global scoped and namespace scoped mode requires updating the deployment/RBAC and restarting or redeploying the operator.
- Updating AWS IAM permissions belongs to AWS Load Balancer Controller. Restart AWS Load Balancer Controller only if it continues using stale credentials after the IAM role is fixed.

## Limitations

- Only AWS ALB fixed-response mode is currently supported.
- `nginx` and existing `service` response backends are not implemented.
- Fixed-response HTML must be 1024 bytes or smaller.
- With Ingress-name targeting, the target Ingress must be in the same namespace as the `Maintenance` resource.

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
make bump-release VERSION=v1.2.1
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
