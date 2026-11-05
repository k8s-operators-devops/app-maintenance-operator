# Releasing

This repository uses a tag-driven GitHub Actions release pipeline. A stable release produces:

- a multi-architecture controller image at `ghcr.io/k8s-operators-devops/app-maintenance-operator:<version>`;
- the `latest` image tag for stable versions only;
- a GitHub Release with generated release notes; and
- the release-specific `install.yaml` attachment for kubectl installation.

## Release Prerequisites

- The version follows `vMAJOR.MINOR.PATCH`, for example `v1.3.0`.
- The release-preparation commit is merged through the protected `main` branch.
- The `Tests`, `Lint`, and `Build` checks are successful on that exact `main` commit.
- `CHANGELOG.md` has been reviewed and updated with the release notes.

## Prepare the Release

Start from an up-to-date local `main` branch:

```bash
git switch main
git pull --ff-only origin main
make bump-release VERSION=v1.3.0
```

Review the generated changes, including `deploy/install.yaml`, image references, pinned documentation links, GitOps examples, and the manual workflow version example. Update `CHANGELOG.md`, then submit and merge the release-preparation pull request.

## Publish the Release

After the release-preparation pull request is merged and required checks are green, tag the current `main` commit:

```bash
git switch main
git pull --ff-only origin main
git tag -a v1.3.0 -m "v1.3.0"
git push origin v1.3.0
```

The `Publish Release` workflow verifies that the tag is the current `main` commit, validates the required checks, publishes the controller image, and then creates the GitHub Release. Do not create the GitHub Release manually.

Download the attached `install.yaml` from the completed GitHub Release, or use the pinned installation URL in the README.

## Retry a Release

Use the `Publish Release` workflow's manual dispatch only to retry an existing tag. Provide the same immutable version tag, for example `v1.3.0`. The workflow never creates or moves tags, and it fails if the tag does not point to the current validated `main` commit.

The release job is idempotent. If the GitHub Release already exists, a retry does not create a duplicate release.

## Pre-Releases

Pre-release tags such as `v1.3.0-rc.1` follow the same validation and publication flow, but do not update the `latest` image tag. The release workflow automatically marks their GitHub Release as a pre-release.
