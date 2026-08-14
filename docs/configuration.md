# Configuration

## Maintenance Spec

`spec.targetIngress`

Optional legacy mode. Name of the target Ingress in the same namespace as the `Maintenance` resource.

The operator uses this field to find the target Ingress, mirror its rules, and replace every HTTP backend with the maintenance fixed response. Metadata labels on the `Maintenance` resource do not select the target Ingress.

`spec.albGroupName`

Optional preferred mode. Name of the ALB IngressGroup to place into maintenance.

The operator creates a standalone maintenance Ingress with `alb.ingress.kubernetes.io/group.name` set to this value, `alb.ingress.kubernetes.io/group.order: "-1000"`, and a catch-all `/*` fixed-response rule. This avoids coupling maintenance behavior to one existing application Ingress and keeps redirect/application routing layouts out of the Maintenance API.

For AWS Load Balancer Controller correctness, the operator discovers existing Ingresses in the same namespace with the requested group name and mirrors the group's listener-port surface onto the generated maintenance Ingress. This matters because ALB IngressGroup rules only affect the listener ports defined for that Ingress.

Set exactly one of `spec.albGroupName` or `spec.targetIngress`.

`spec.maintenanceMode`

Optional boolean. This is the master switch for maintenance behavior. When `true`, the operator creates or reconciles maintenance resources immediately unless `spec.schedule` narrows the active window. When `false` or omitted, the operator removes generated maintenance resources and ignores `spec.schedule`.

`spec.response`

Optional response configuration. If omitted, the operator uses a default fixed-response HTML body.

`spec.response.backend`

Optional string. Supported value: `fixed-response`. Other backend modes are not implemented in this release.

`spec.response.html`

Optional HTML body for the ALB fixed response. The body must be 1024 bytes or smaller.

`spec.response.useNginx`

Reserved for future compatibility. Not implemented in this release.

`spec.response.serviceName`

Reserved for future compatibility. Not implemented in this release.

`spec.priority`

Reserved API field from earlier designs. The controller always uses `alb.ingress.kubernetes.io/group.order: "-1000"` for the generated maintenance Ingress.

`spec.schedule`

Optional maintenance window. `start` and `end` are RFC3339 timestamps. The controller enables maintenance inside the window and disables it outside the window only when `spec.maintenanceMode: true`. `start` or `end` may be omitted for open-ended schedules.

End users choose the timezone by writing the timestamp with either `Z` for UTC or an explicit offset such as `-04:00` or `+05:30`.

When both fields are set, `end` must be after `start`. Invalid windows are rejected with `status.phase: Failed` and reason `InvalidSchedule`.

Example:

```yaml
spec:
  albGroupName: <alb-ingress-group-name>
  maintenanceMode: true
  schedule:
    start: "2026-07-20T22:00:00Z"
    end: "2026-07-20T23:00:00Z"
```

Equivalent example with an explicit local timezone offset:

```yaml
spec:
  albGroupName: <alb-ingress-group-name>
  maintenanceMode: true
  schedule:
    start: "2026-07-20T18:00:00-04:00"
    end: "2026-07-20T19:00:00-04:00"
```

## ALB Group Mode

Group mode is the preferred production model:

```yaml
spec:
  albGroupName: <alb-ingress-group-name>
  maintenanceMode: true
```

Advantages:

- users do not need to know which application Ingress owns a route;
- redirect and application Ingresses can stay separate;
- the operator does not copy tenant-specific annotations or paths;
- maintenance intent maps directly to the ALB IngressGroup boundary;
- HTTPS listeners are covered when existing group members declare them through `alb.ingress.kubernetes.io/listen-ports` or certificate-based defaults.

In shared ALB groups, group mode affects the group-level routing surface. Use separate ALB IngressGroup names per tenant when tenant isolation is required. At least one existing group member Ingress must be present in the same namespace as the `Maintenance` resource so the operator can discover listener ports.

Discover available group names:

```sh
kubectl get ingress -n <application-namespace> \
  -o custom-columns=NAME:.metadata.name,GROUP:.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name,LISTEN_PORTS:.metadata.annotations.alb\.ingress\.kubernetes\.io/listen-ports
```

## Legacy Target Ingress Mode

When `spec.targetIngress` is used, the target Ingress must:

- exist in the same namespace as the `Maintenance` resource;
- be ALB-managed through `spec.ingressClassName: alb` or `kubernetes.io/ingress.class: alb`;
- define the ALB IngressGroup ID/name with `alb.ingress.kubernetes.io/group.name`;
- contain at least one HTTP path or a valid default backend.

The operator copies ALB-level annotations that are relevant to the load balancer and removes annotations that conflict with fixed-response behavior.

The group name is mandatory because the operator creates a separate maintenance Ingress that joins the same ALB IngressGroup as the existing application Ingress. If the target Ingress is not grouped, the controller reports `InvalidConfiguration` and does not create the maintenance overlay.

Verify the group name before scheduling or enabling maintenance:

```sh
kubectl describe ingress <target-ingress-name> -n <application-namespace>
```

Confirm the annotations include `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`.

## Namespace-Scoped Operation

By default, the global scoped install manifest uses cluster-scoped manager RBAC so one controller can reconcile `Maintenance` resources across application namespaces. This is convenient for platform teams, but it increases blast radius if the controller service account is compromised.

For stricter least-privilege environments, the manager supports `WATCH_NAMESPACE`. When this environment variable is set, the controller-runtime cache is restricted to that namespace list. Multiple namespaces can be provided as a comma-separated list.

Examples:

```sh
WATCH_NAMESPACE=payments
WATCH_NAMESPACE=payments,checkout
```

The `config/namespaced` Kustomize profile runs the controller in its own namespace and sets `WATCH_NAMESPACE` from the pod namespace. It uses namespaced `Role` and `RoleBinding` objects for manager permissions instead of the default manager `ClusterRole` and `ClusterRoleBinding`.

Pinned Kustomize install:

```bash
kubectl apply -k https://github.com/k8s-operators-devops/app-maintenance-operator/config/namespaced?ref=v1.1.1
```

With this profile, the operator watches only the namespace where it is installed. The `Maintenance` resource and generated maintenance Ingress must live in that same namespace. In legacy `targetIngress` mode, the target Ingress and backup ConfigMap must also live there.

For a one-command namespace-scoped install, Helm is the preferred future packaging direction. This repository does not publish a Helm chart yet, so use the `kubectl apply -k` command above for namespace-scoped installs today. The example below documents the intended chart interface:

```bash
helm install app-maintenance-operator <chart> \
  --namespace <application-namespace> \
  --create-namespace \
  --set scope=namespaced
```

The planned default Helm install should stay global scoped so it matches the default manifest behavior:

```bash
helm install app-maintenance-operator <chart> \
  --namespace alb-maintenance-operator \
  --create-namespace
```

Important boundaries:

- CRDs are cluster-scoped Kubernetes resources and still require cluster-level installation permissions.
- The namespaced profile can reconcile only `Maintenance`, generated maintenance Ingress, and generated backup ConfigMap resources in the namespace where the operator is installed.
- In legacy `targetIngress` mode, the target Ingress must still live in the same namespace as the `Maintenance` resource.
- The namespaced profile disables the secured metrics endpoint by default to avoid adding cluster-level TokenReview and SubjectAccessReview permissions back into the runtime service account.
- Do not put `watchNamespace` in the `Maintenance` spec. Watch scope is deployment and RBAC configuration, not application maintenance intent.

## GitOps Considerations

The operator creates temporary maintenance resources dynamically. In GitOps-managed namespaces, tools such as Argo CD or Flux may report these resources as drift. If automated pruning is enabled, the GitOps controller may delete the generated maintenance overlay before the scheduled window is complete.

Production GitOps users should explicitly ignore or exclude operator-generated resources from prune decisions. At minimum, review ignore rules for generated maintenance Ingresses, backup ConfigMaps owned by a `Maintenance` resource, and resources managed by the operator service account.

## Examples

Enable maintenance:

```sh
kubectl apply -f samples/maintenance-enable.yaml
```

Disable maintenance:

```sh
kubectl apply -f samples/maintenance-disable.yaml
```

Schedule maintenance:

```sh
kubectl apply -f samples/maintenance-scheduled.yaml
```

Patch an existing resource:

```sh
kubectl patch maintenance <maintenance-name> \
  -n <application-namespace> \
  --type merge \
  -p '{"spec":{"maintenanceMode":false}}'
```

## Status

`status.phase`

- `Enabled`: maintenance overlay is active.
- `Disabled`: generated maintenance resources have been removed.
- `Failed`: reconciliation failed or configuration is invalid.
- `Pending`: reserved phase value.

`status.message`

Human-readable explanation of the current state.

`status.conditions`

Uses standard `metav1.Condition` shape. The controller sets the `Ready` condition with stable reasons such as:

- `MaintenanceEnabled`
- `MaintenanceDisabled`
- `InvalidConfiguration`
- `TargetIngressNotFound`
- `BackupCreationFailed`
- `MaintenanceIngressReconcileFailed`
- `CleanupFailed`

`status.backupCreated`

Indicates whether the operator has created or accepted an owned backup ConfigMap.

`status.backupResourceName`

Name of the backup ConfigMap containing the original target Ingress JSON. This is used only in legacy `targetIngress` mode.

`status.targetIngressResourceVersion`

ResourceVersion of the target Ingress observed when maintenance was enabled. This is used only in legacy `targetIngress` mode.
