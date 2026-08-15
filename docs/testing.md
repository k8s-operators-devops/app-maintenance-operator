# Testing

`app-maintenance-operator` is an ALB maintenance operator for Kubernetes. It creates AWS Load Balancer Controller-compatible maintenance overlays for ALB IngressGroups without mutating the original application Ingress.

Start with the [project README](../README.md) for installation and usage, or open the [GitHub Pages documentation](https://k8s-operators-devops.github.io/app-maintenance-operator/) for the public landing page.

## Local Validation Without a Cluster

These commands validate source code, controller behavior, generated code, and bundle packaging without requiring access to a Kubernetes cluster:

```sh
go fmt ./...
go vet ./...
go test ./...
make generate
make manifests
make build
make bundle
git diff --check
```

The controller tests include unit coverage and envtest coverage for core reconciliation behavior, including generated Ingress recreation and finalizer cleanup ordering.

On a clean checkout, direct `go test ./...` may skip envtest-backed Ginkgo specs if local envtest binaries are not installed. Run `make test` or `make verify` to provision those ignored local binaries and execute the full controller test suite.

## Validate the Install Bundle

If `kubectl` is available, run a client-side manifest check:

```sh
kubectl apply --dry-run=client --validate=false -f deploy/install.yaml
```

This does not require a live cluster when client-side dry-run can parse the manifest locally.

## Cluster Validation From Another Machine

From a workstation, CI runner, or bastion with cluster access:

```sh
kubectl apply -f deploy/install.yaml
kubectl get pods -n alb-maintenance-operator
kubectl logs -n alb-maintenance-operator \
  deployment/alb-maintenance \
  -c manager
```

## Enable Maintenance

Update `samples/maintenance-enable.yaml` so `<maintenance-name>`, `<application-namespace>`, and `<alb-ingress-group-name>` match a non-production ALB IngressGroup.

```sh
kubectl apply -f samples/maintenance-enable.yaml
kubectl get maintenance -n <application-namespace>
kubectl describe maintenance <maintenance-name> -n <application-namespace>
kubectl get ingress -n <application-namespace>
kubectl get configmap -n <application-namespace>
```

Confirm the generated maintenance Ingress:

- exists separately from the application Ingress;
- has `alb.ingress.kubernetes.io/group.order: "-1000"`;
- has `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>`;
- has one catch-all `/*` path that uses `maintenance/use-annotation`.

Confirm at least one application Ingress declares the ALB IngressGroup:

```sh
kubectl get ingress -n <application-namespace> \
  -o custom-columns=NAME:.metadata.name,GROUP:.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name,LISTEN_PORTS:.metadata.annotations.alb\.ingress\.kubernetes\.io/listen-ports
```

Look for `alb.ingress.kubernetes.io/group.name: <alb-ingress-group-name>` in the annotations.

To validate direct Ingress-name targeting instead, update and apply `samples/maintenance-enable-ingress.yaml` with `<target-ingress-name>` in the same namespace.

## Curl Verification

```sh
curl -i https://your-hostname.example.com/
```

Expected maintenance result:

```text
HTTP/2 503
content-type: text/html
```

## Disable Maintenance

```sh
kubectl patch maintenance <maintenance-name> \
  -n <application-namespace> \
  --type merge \
  -p '{"spec":{"maintenanceMode":false}}'
```

Verify cleanup:

```sh
kubectl get ingress -n <application-namespace>
kubectl get configmap -n <application-namespace>
kubectl describe maintenance <maintenance-name> -n <application-namespace>
```

For ALB IngressGroup targeting, the generated maintenance Ingress should be gone and no backup ConfigMap should be created. For Ingress-name targeting, any generated backup ConfigMap should also be gone. The application Ingress should remain unchanged.

## Schedule Maintenance

Update `samples/maintenance-scheduled.yaml` so `<maintenance-name>`, `<application-namespace>`, `<alb-ingress-group-name>`, `spec.maintenanceMode`, `spec.schedule.start`, and `spec.schedule.end` match a non-production ALB IngressGroup and maintenance window. Use RFC3339 timestamps such as `2026-09-01T22:00:00Z` for UTC or `2026-09-01T18:00:00-04:00` for an ET offset.

```sh
kubectl apply -f samples/maintenance-scheduled.yaml
kubectl describe maintenance <maintenance-name> -n <application-namespace>
```

Before the start time, the resource should report `Pending`. During the window, it should report `Enabled`. At or after the end time, it should report `Disabled` and generated resources should be removed.

To validate scheduled Ingress-name targeting instead, update and apply `samples/maintenance-scheduled-ingress.yaml`.

## Finalizer Checks

Delete the `Maintenance` resource:

```sh
kubectl delete maintenance <maintenance-name> -n <application-namespace>
```

If deletion appears delayed, inspect:

```sh
kubectl get maintenance <maintenance-name> -n <application-namespace> -o yaml
kubectl get ingress -n <application-namespace>
kubectl get configmap -n <application-namespace>
```

The controller is expected to delete the generated maintenance Ingress first, wait until it is gone, delete any owned backup ConfigMap, and then remove the finalizer.

## Controller Logs

```sh
kubectl logs -n alb-maintenance-operator \
  deployment/alb-maintenance \
  -c manager
```

Look for invalid configuration errors such as missing targeting mode, both targeting modes being set, missing target Ingress with Ingress-name targeting, missing ALB group name with Ingress-name targeting, non-ALB target Ingress, or fixed-response HTML exceeding 1024 bytes.
