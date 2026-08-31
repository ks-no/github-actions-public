# github-actions-public

Central library of reusable workflows and composite actions for Github Actions.

The reference for writing Actions workflows is available at the [Github docs](https://docs.github.com/en/actions/reference/workflows-and-actions).

## Reusable workflows

Most projects should be able to use these for their CI/CD pipelines.

To use a reusable workflow, write `ks-no/github-actions-public/.github/workflows/<workflow-name>.yml@main` under a
`jobs.<job-name>.uses` key in your workflow file. See the template files in `./caller-templates/` for examples of how to call these workflows.

If your repo demands that all Actions workflow calls are pinned to a commit SHA, replace "main" with the full, latest commit SHA of this repo.

### For JVM-based projects:

- java-service-build *(for deployable services)*
- java-library-internal-build *(for private libraries)*
- java-library-maven-central-build *(for public libraries)*

### For .NET-based libraries:

- dotnet-library-build

### For Node.js-based services:

- nodejs-service-build

### Various

- deploy *(to deploy a service with Helm; the Helm-chart values must already have been populated)*
- open-api-specs *(to publish OpenAPI spec files for spec-first projects)*
- license-check *(to check project licenses against Dependency-Track)*
- zizmor-audit *(to lint workflow files)*

## Composites

There are a large number of composite actions which can be used in custom workflows.

To use a composite action, write `ks-no/github-actions-public/<workflow-name>@main` under a
`jobs.<job-name>.steps.[step].uses` key in your workflow file.

The same caveat about commit SHA's as above applies here.

### Wrappers

Some composites are simply wrappers around widely used third party actions, to avoid the hassle of updating commit SHA's.
These wrappers are:

- checkout (for `actions/checkout`)
- upload-artifact (for `actions/upload-artifact`)
- download-artifact (for `actions/download-artifact`)
- setup-java (for `actions/setup-java`)

More may be added in the future.

## Runners

KS Digital utilizes both Github's runners (for public repos), and self-hosted runners (for private repos). All runners are Linux-based.
To use a Github-hosted runner in a custom workflow, write the label `ubuntu-latest` under a `jobs.<job-name>.runs-on` key;
for self-hosted runners, the label is `[self-hosted, x64]`. In reusable workflows, the runner type is already specified.

### Large runners

Some services may require more memory in order to be built. The label `x64-large` is used to request a large runner.
This is also accomplished by filling in `big-runner: true` under a workflow dispatch to `java-service-build`.

### open-api-specs

Some spec files are placed in public repos. If this is the case, fill in `is_public: true` under a workflow dispatch to `open-api-specs`.

### Test-runners (for development only)

Request a test runner by specifying the label `[self-hosted, test]` in a custom workflow,
or `@test-runner` in a call to a reusable workflow.
