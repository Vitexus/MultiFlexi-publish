# MultiFlexi-publish Pipeline

This repository contains a Jenkins pipeline for publishing Debian packages (.deb) to an Aptly-managed repository.

## Overview

The pipeline automates the following steps:
1. Receives or builds Debian package files (`*.deb`).
2. Adds the packages to an Aptly repository.
3. Publishes the updated repository for client access.

## Requirements

- Jenkins server with access to the build artifacts.
- Aptly installed and configured on the target machine.
- Proper permissions for Jenkins to run Aptly commands.

## Usage

1. Place your generated `.deb` packages in the designated workspace or artifact directory.
2. Trigger the Jenkins pipeline.
3. The pipeline will:
   - Add the new packages to the Aptly repository.
   - Update and publish the repository.

## How to Trigger the Pipeline

To initiate the publishing process from an upstream Jenkins job, use the following Groovy code snippet:

```groovy
if (!currentBuild.result || currentBuild.result == 'SUCCESS') {
    build job: 'MultiFlexi-publish',
      wait: false,
      parameters: [
        string(name: 'UPSTREAM_JOB', value: env.JOB_NAME),
        string(name: 'UPSTREAM_BUILD', value: env.BUILD_NUMBER),
        string(name: 'REMOTE_SSH', value: 'multirepo@repo.multiflexi.eu'),
        string(name: 'REMOTE_REPO_DIR', value: '/srv/repo'),
        string(name: 'COMPONENT', value: 'main'),
        string(name: 'DEB_DIST', value: '')
      ]
}
```

This code triggers the `MultiFlexi-publish` job with the required parameters:
- `UPSTREAM_JOB`: Name of the upstream job.
- `UPSTREAM_BUILD`: Build number of the upstream job.
- `REMOTE_SSH`: SSH user and host for the repository server.
- `REMOTE_REPO_DIR`: Directory on the remote server where the repository is located.
- `COMPONENT`: Repository component (e.g., `main`).
- `DEB_DIST`: Debian distribution (leave empty if not needed).

## Example Jenkinsfile

The `Jenkinsfile` in this repository contains the necessary steps to automate the process. Adjust paths and repository names as needed for your environment.

## Notes

- Ensure Aptly is properly configured and the repository exists before running the pipeline.
- You may need to update credentials or permissions for Jenkins to interact with Aptly.
