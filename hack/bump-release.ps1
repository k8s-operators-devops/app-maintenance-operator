param(
    [string]$Version
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Version) -or $Version -notmatch '^v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    throw "Version must look like v0.1.2 or v0.1.2-alpha.1. Got: $Version"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$image = "ghcr.io/k8s-operators-devops/app-maintenance-operator"

$updates = @(
    @{
        Path = "README.md"
        Patterns = @(
            @{ From = 'app-maintenance-operator/v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?/deploy/install\.yaml'; To = "app-maintenance-operator/$Version/deploy/install.yaml" },
            @{ From = 'app-maintenance-operator/latest/deploy/install\.yaml'; To = "app-maintenance-operator/$Version/deploy/install.yaml" },
            @{ From = 'ref=v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "ref=$Version" },
            @{ From = 'make bump-release VERSION=v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "make bump-release VERSION=$Version" },
            @{ From = 'For `v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?`:'; To = "For ``$Version``:" },
            @{ From = 'git tag -a v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)? -m "v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?"'; To = "git tag -a $Version -m `"$Version`"" },
            @{ From = 'git push origin v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "git push origin $Version" },
            @{ From = [regex]::Escape($image) + ':v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "$image`:$Version" }
        )
    },
    @{
        Path = "docs/index.html"
        Patterns = @(
            @{ From = 'app-maintenance-operator/v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?/deploy/install\.yaml'; To = "app-maintenance-operator/$Version/deploy/install.yaml" },
            @{ From = 'app-maintenance-operator/latest/deploy/install\.yaml'; To = "app-maintenance-operator/$Version/deploy/install.yaml" },
            @{ From = '<h2>Install v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?</h2>'; To = "<h2>Install $Version</h2>" },
            @{ From = 'Copy v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)? install command'; To = "Copy $Version install command" },
            @{ From = '<span>v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?</span>'; To = "<span>$Version</span>" }
        )
    },
    @{
        Path = "docs/configuration.md"
        Patterns = @(
            @{ From = 'ref=v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "ref=$Version" }
        )
    },
    @{
        Path = "docs/releasing.md"
        Patterns = @(
            @{ From = 'v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = $Version }
        )
    },
    @{
        Path = "deploy/install.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" },
            @{ From = 'value: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "value: $Version" },
            @{ From = [regex]::Escape($image) + ':v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "$image`:$Version" }
        )
    },
    @{
        Path = ".github/workflows/publish-image.yml"
        Patterns = @(
            @{ From = 'for example v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "for example $Version" },
            @{ From = 'default: "v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?"'; To = "default: `"$Version`"" }
        )
    },
    @{
        Path = "examples/gitops/argocd/application.yaml"
        Patterns = @(
            @{ From = 'targetRevision: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "targetRevision: $Version" }
        )
    },
    @{
        Path = "examples/gitops/flux/kustomization.yaml"
        Patterns = @(
            @{ From = 'tag: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "tag: $Version" }
        )
    },
    @{
        Path = ".github/ISSUE_TEMPLATE/bug_report.yml"
        Patterns = @(
            @{ From = 'operator v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "operator $Version" }
        )
    },
    @{
        Path = "config/default/kustomization.yaml"
        Patterns = @(
            @{ From = 'newTag: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "newTag: $Version" }
        )
    },
    @{
        Path = "config/namespaced/kustomization.yaml"
        Patterns = @(
            @{ From = 'newTag: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "newTag: $Version" }
        )
    },
    @{
        Path = "config/manager/manager.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" },
            @{ From = 'value: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "value: $Version" }
        )
    },
    @{
        Path = "config/prometheus/monitor.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/default/metrics_service.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/network-policy/allow-metrics-traffic.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/namespaced/service_account.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/namespaced/manager_role.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/namespaced/manager_role_binding.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/namespaced/manager_namespace_patch.yaml"
        Patterns = @(
            @{ From = 'value: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "value: $Version" }
        )
    },
    @{
        Path = "config/namespaced/leader_election_role.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/namespaced/leader_election_role_binding.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/rbac/service_account.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/rbac/role_binding.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/rbac/leader_election_role.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/rbac/leader_election_role_binding.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/rbac/namespaced_manager_role.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    },
    @{
        Path = "config/rbac/namespaced_manager_role_binding.yaml"
        Patterns = @(
            @{ From = 'app\.kubernetes\.io/version: v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?'; To = "app.kubernetes.io/version: $Version" }
        )
    }
)

foreach ($update in $updates) {
    $path = Join-Path $repoRoot $update.Path
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing expected file: $($update.Path)"
    }

    $content = Get-Content -LiteralPath $path -Raw
    foreach ($pattern in $update.Patterns) {
        $content = [regex]::Replace($content, $pattern.From, $pattern.To)
    }
    Set-Content -LiteralPath $path -Value $content -NoNewline
    Write-Host "Updated $($update.Path)"
}

Write-Host ""
Write-Host "Release references now point to $Version."
Write-Host "Review CHANGELOG.md manually and add the release notes before tagging."
