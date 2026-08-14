# Architecture

## At a Glance

```mermaid
flowchart LR
    User[End user] --> ALB[AWS ALB]
    ALB --> Group[ALB IngressGroup]
    Group --> Maint[Generated maintenance Ingress<br/>group.order -1000]
    Maint --> Fixed[ALB fixed-response<br/>HTTP 503]
    Group -. lower precedence .-> App[Original application Ingress]
    App -. unchanged .-> Service[Application Service]
    Service -. unchanged .-> Pods[Application Pods]
```

The operator gives the ALB a higher-priority maintenance rule without rewriting the application team's Ingress. That is the whole value proposition.

## Maintenance Custom Resource

The `Maintenance` custom resource is the operator API for enabling or disabling maintenance mode for an ALB IngressGroup. The preferred targeting field is `spec.albGroupName`; legacy target-Ingress mirroring remains available through `spec.targetIngress`.

The ALB IngressGroup must already exist through one or more AWS Load Balancer Controller-managed Ingresses.

## Reconciliation Flow

When a `Maintenance` resource is created or updated, the controller:

1. Adds a finalizer to the `Maintenance` resource.
2. Builds the fixed-response ALB action from `spec.response`.
3. In group mode, discovers existing same-namespace IngressGroup members, resolves their listener ports, and creates or reconciles a standalone catch-all maintenance Ingress for `spec.albGroupName`.
4. In legacy target-Ingress mode, reads the target Ingress, validates it, creates a one-time backup ConfigMap, and mirrors its rules into the generated maintenance Ingress.
5. Updates status phase, message, and the standard `Ready` condition.

On disable, the controller deletes the generated maintenance Ingress and any backup ConfigMap. It does not patch, replace, or restore the original application Ingress.

On deletion, the controller deletes the generated maintenance Ingress first, waits until it is gone, deletes the backup ConfigMap, and then removes the finalizer.

## Overlay Ingress Model

The operator uses an overlay model. The application Ingress remains the business-owned routing object. The maintenance Ingress is a temporary operator-owned object that joins the same ALB group and takes precedence.

This model avoids a risky anti-pattern: mutating production application routing state and later attempting to restore it from a backup. In cloud operations, that kind of restore logic is a sharp edge. The operator keeps the application Ingress read-only during normal enable and disable.

## ALB IngressGroup Behavior

AWS Load Balancer Controller merges Ingresses with the same `alb.ingress.kubernetes.io/group.name` into one ALB rule set. Lower `alb.ingress.kubernetes.io/group.order` values take precedence.

The generated maintenance Ingress:

- uses `spec.albGroupName` directly, or copies the target Ingress group name in legacy mode;
- sets `alb.ingress.kubernetes.io/group.order: "-1000"`;
- sets `alb.ingress.kubernetes.io/listen-ports` from the discovered ALB group listener ports;
- removes inherited ALB action annotations;
- removes target-group-specific health check/backend annotations;
- adds only `alb.ingress.kubernetes.io/actions.maintenance`.

## Normal Traffic Flow

```mermaid
flowchart LR
    Client --> ALB
    ALB --> AppIngress[Application Ingress]
    AppIngress --> Service[Application Service]
    Service --> Pods[Application Pods]
```

## Maintenance Traffic Flow

```mermaid
flowchart LR
    Client --> ALB
    ALB --> MaintenanceIngress[Generated Maintenance Ingress]
    MaintenanceIngress --> FixedResponse[ALB fixed-response 503]
    AppIngress[Application Ingress] -. remains unchanged .- Service[Application Service]
```

## Watches

The controller watches:

- `Maintenance` resources;
- owned backup ConfigMaps;
- owned generated maintenance Ingresses;
- target Ingress changes filtered by the `spec.targetIngress` field index.

Owned Ingress watches repair drift or manual deletion of the generated maintenance Ingress. Target Ingress watches allow legacy maintenance overlays to be reconciled when the source application Ingress changes.
