# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

MultiFlexi-publish is a Jenkins CI/CD pipeline for publishing Debian packages (.deb) to an Aptly-managed repository. It's part of the larger MultiFlexi ecosystem - a comprehensive PHP-based task scheduling and automation framework for accounting and business system integrations.

## Project Architecture

MultiFlexi-publish operates as a downstream publishing system that:
1. Fetches .deb package artifacts from upstream Jenkins jobs
2. Uploads packages to an Aptly repository server via SSH
3. Publishes the updated repository for client access

### Key Components

- **Jenkinsfile**: Main pipeline definition using Jenkins Pipeline DSL
- **create_jenkins_publish_job.sh**: Script to create/update Jenkins job via REST API
- **README.md**: Documentation and usage instructions

## Common Development Commands

### Jenkins Job Management
```bash
# Set required environment variables for Jenkins API access
export JENKINS_URL="https://your-jenkins-server.com"
export JENKINS_USER="your-username"  
export JENKINS_TOKEN="your-api-token"

# Create or update the MultiFlexi-publish job
./create_jenkins_publish_job.sh
```

### Pipeline Execution
The pipeline is typically triggered from upstream jobs with parameters:
```groovy
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
```

### Local Testing and Development
```bash
# Test SSH connectivity to repository server
ssh -o StrictHostKeyChecking=no multirepo@repo.multiflexi.eu "ls -la /srv/repo"

# Verify Jenkins job configuration
curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/job/MultiFlexi/job/MultiFlexi-publish/config.xml"

# View job console output
curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/job/MultiFlexi/job/MultiFlexi-publish/lastBuild/consoleText"
```

## High-Level Architecture

This repository is part of the MultiFlexi ecosystem which includes:
- **multiflexi-core**: Core PHP library and shared components
- **multiflexi-database**: Database schema and migrations
- **multiflexi-executor**: Job execution engine
- **multiflexi-scheduler**: Task scheduling system
- **multiflexi-cli**: Command-line interface tools
- **multiflexi-web**: Web interface (main MultiFlexi repository)
- **MultiFlexi-publish**: CI/CD pipeline for package publishing (this repository)

### Package Publishing Flow
1. Upstream Jenkins jobs build .deb packages for MultiFlexi components
2. On successful build, upstream triggers MultiFlexi-publish job
3. Pipeline fetches artifacts using Jenkins copyArtifacts plugin
4. Packages are uploaded to remote Aptly repository server
5. Aptly processes packages into distribution-specific repositories
6. Repository metadata is updated and published

### Infrastructure Dependencies
- Jenkins server with copyArtifacts plugin
- Remote Aptly repository server with SSH access
- SSH key-based authentication (passwordless)
- Aptly repositories pre-configured for target distributions

## Key Technical Patterns

### Jenkins Pipeline Structure
- Uses declarative pipeline syntax with parameters
- Implements artifact fetching with flattening for simplicity
- Handles multiple .deb files with automatic distribution detection
- Uses SSH for remote operations with proper error handling
- Implements idempotent operations (can be safely re-run)

### Distribution Detection
Package distribution is extracted from filename pattern:
```
package~distro_version_architecture.deb
```
Example: `multiflexi~bookworm_1.0.0_all.deb` → distribution: `bookworm`

### Aptly Integration
- Repositories follow naming pattern: `{distribution}-{component}-multiflexi`
- Uses `--force-replace` and `--remove-files` flags for safe updates
- Supports multiple distributions simultaneously

## Development Workflow

1. **Pipeline Development**: Edit `Jenkinsfile` for pipeline logic changes
2. **Job Configuration**: Modify `create_jenkins_publish_job.sh` for parameter or job settings changes
3. **Testing**: Use Jenkins Blue Ocean or classic UI to monitor pipeline execution
4. **Documentation**: Update README.md for usage instructions

The repository follows Infrastructure as Code principles with pipeline definition versioned alongside configuration scripts.

## Agent Operation Rule: Always Commit and Push

- After applying any change to this repository (code, scripts, or docs), immediately:
  - `git add -A`
  - `git commit -m "<concise change summary>"`
  - `git push origin HEAD`
- Prefer a clear, actionable commit message (present tense, concise summary on the first line).
- If multiple related edits are made in sequence, it is acceptable to push once at the end of the sequence, but do not leave the working tree dirty.
- If a push is rejected due to remote updates, perform `git pull --rebase` and retry `git push`.
- Do not commit any credentials or secrets.
