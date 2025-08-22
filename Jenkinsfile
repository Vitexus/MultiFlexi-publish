
import groovy.json.JsonSlurperClassic

pipeline {
  agent any
parameters {
    string(name: 'JENKINS_URL', defaultValue: 'https://jenkins.proxy.spojenet.cz', description: 'Jenkins base URL')
    string(name: 'UPSTREAM_JOB', defaultValue: '', description: 'Upstream job name or full path (e.g., composer-debian or MultiFlexi/composer-debian)')
    string(name: 'UPSTREAM_BUILD', defaultValue: '', description: 'Upstream build number')
    string(name: 'REMOTE_SSH', defaultValue: 'multirepo@repo.multiflexi.eu', description: 'SSH user@host of repository server')
    string(name: 'REMOTE_REPO_DIR', defaultValue: '/srv/repo', description: 'Repository base directory')
    string(name: 'COMPONENT', defaultValue: 'main', description: 'Repository component')
    string(name: 'DEB_DIST', defaultValue: '', description: 'Debian/Ubuntu distributions (space or comma separated), can be empty')
  }
  options { timestamps() }
  stages {
stage('Fetch artifacts') {
      steps {
        // Clean previous .deb files from workspace to avoid re-uploading old builds
        sh 'rm -f *.deb 2>/dev/null || true'
        script {
          def upstream = params.UPSTREAM_JOB?.trim(); if (!upstream) { error('UPSTREAM_JOB is required') }
          def buildNum = params.UPSTREAM_BUILD?.trim(); if (!buildNum) { error('UPSTREAM_BUILD is required') }
          def projectPath = upstream.contains('/') ? upstream : "MultiFlexi/${upstream}"
          echo "Copying .deb artifacts from ${projectPath} #${buildNum}"
          
          try {
            copyArtifacts projectName: projectPath, selector: specific(buildNum), filter: '**/*.deb', flatten: true, optional: true
            echo "Successfully copied artifacts from ${projectPath}"
          } catch (Exception e) {
            echo "Warning: Failed to copy artifacts from ${projectPath}: ${e.getMessage()}"
            echo "This may be due to:"
            echo "  - Project '${projectPath}' does not exist"
            echo "  - Build #${buildNum} does not exist or has no .deb artifacts"
            echo "  - Insufficient permissions to access the project"
            echo "Continuing with empty artifact list..."
          }
        }
      }
    }
    stage('Publish to repo') {
      steps {
        script {
          def hasDebs = sh(returnStatus: true, script: 'ls -1 *.deb >/dev/null 2>&1') == 0
          if (!hasDebs) {
            echo 'No .deb files to publish; skipping'
            return
          }
        }
        // Use system SSH key of Jenkins user (passwordless access configured on server)
sh label: 'Upload and publish', script: '''
          set -e
          DEST="${REMOTE_SSH}"
          REMOTE_REPO_DIR="${REMOTE_REPO_DIR}"
          COMPONENT="${COMPONENT}"
          DEB_DIST="${DEB_DIST:-}"

          ssh -o StrictHostKeyChecking=no "$DEST" "mkdir -p \"$REMOTE_REPO_DIR/incoming\""
          for f in *.deb; do
            [ -e "$f" ] || continue
            scp -o StrictHostKeyChecking=no "$f" "$DEST:$REMOTE_REPO_DIR/incoming/"
          done
          # Add all uploaded packages to their respective distro repos using aptly, following official documentation
          DISTS=""
          for f in *.deb; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            dist="${base#*~}"; dist="${dist%%_*}"
            repo="${dist}-main-multiflexi"
            # Use -force-replace and -remove-files as recommended by aptly docs
            ssh -o StrictHostKeyChecking=no "$DEST" "aptly repo add -force-replace -remove-files '$repo' '$REMOTE_REPO_DIR/incoming/$base'" || true
            case " $DISTS " in *" $dist "*) ;; *) DISTS="$DISTS $dist";; esac
            rm -f "$f"
          done

        '''
      }
    }
  }
}

