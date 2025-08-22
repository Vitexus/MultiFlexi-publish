
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
          // Copy Artifact plugin often requires '/job/.../job/...' style for foldered jobs
          def projectPathCA = "/job/${projectPath.replace('/', '/job/')}"
          echo "Copying .deb artifacts from ${projectPath} (#${buildNum})"
          echo "Resolved Copy Artifact path: ${projectPathCA}"
          
          // Try multiple approaches to get artifacts
          def copySuccess = false
          
          // Method 1: Direct project path using '/job/..' style
          try {
            copyArtifacts projectName: projectPathCA, selector: specific(buildNum), filter: '**/dist/debian/*.deb, **/*.deb', flatten: true, optional: true
            echo "Successfully copied artifacts from ${projectPathCA}"
            copySuccess = true
          } catch (Exception e1) {
            echo "Method 1 failed: ${e1.getMessage()}"
            
            // Method 2: Try without MultiFlexi prefix if it was added (both plain and '/job/' styles)
            if (projectPath.startsWith('MultiFlexi/')) {
              def simpleJobName = projectPath.replace('MultiFlexi/', '')
              def simpleJobCA = "/job/${simpleJobName.replace('/', '/job/')}"
              try {
                echo "Trying alternate project path (CA): ${simpleJobCA}"
                copyArtifacts projectName: simpleJobCA, selector: specific(buildNum), filter: '**/dist/debian/*.deb, **/*.deb', flatten: true, optional: true
                echo "Successfully copied artifacts from ${simpleJobCA}"
                copySuccess = true
              } catch (Exception e2) {
                echo "Method 2 failed: ${e2.getMessage()}"
              }
            }
          }
          
          if (!copySuccess) {
            echo "Warning: All artifact copy methods failed for project '${projectPath}'"
            echo "Attempting direct file system access as fallback..."
            
            // Method 3: Direct file system access as last resort (use workspace path, not '/job' URL path)
            try {
              def workspacePattern = "/var/lib/jenkins/workspace/${projectPath}/"
              def foundFiles = sh(returnStdout: true, script: "find \\\"${workspacePattern}\\\" -name '*.deb' -type f 2>/dev/null | head -10 || echo 'NO_FILES_FOUND'").trim()
              
              if (foundFiles != 'NO_FILES_FOUND' && foundFiles != '') {
                foundFiles.split('\n').each { file ->
                  if (file.trim()) {
                    sh "cp \\\"${file}\\\" ./"
                    echo "Copied via direct access: ${file}"
                    copySuccess = true
                  }
                }
              }
            } catch (Exception e3) {
              echo "Method 3 (direct access) failed: ${e3.getMessage()}"
            }
          }
          
          if (!copySuccess) {
            echo "ERROR: All artifact copy methods failed for project '${projectPath}'"
            echo "This may be due to:"
            echo "  - Project permissions: '${projectPath}' must allow artifact copying"
            echo "  - Build #${buildNum} has no .deb artifacts"
            echo "  - copyArtifacts plugin configuration issues"
            echo ""
            echo "To fix this:"
            echo "  1. In ${projectPath} job configuration:"
            echo "     - Enable 'Archive the artifacts' with pattern: *.deb"
            echo "     - Add 'Permit artifact copy' post-build action"
            echo "     - Allow projects: MultiFlexi-publish or MultiFlexi/*"
            echo "  2. Check Jenkins global security settings"
            echo "  3. Verify copyArtifacts plugin is installed and enabled"
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
        // Test SSH connectivity first
        script {
          def sshTest = sh(returnStatus: true, script: "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${params.REMOTE_SSH} 'echo SSH connection successful'")
          if (sshTest != 0) {
            echo "ERROR: Cannot connect to repository server ${params.REMOTE_SSH}"
            echo "This may be due to:"
            echo "  - SSH account '${params.REMOTE_SSH}' is disabled or not available"
            echo "  - Network connectivity issues"
            echo "  - SSH keys not properly configured"
            echo "  - Repository server is down"
            echo ""
            echo "Please verify:"
            echo "  1. SSH access: ssh ${params.REMOTE_SSH}"
            echo "  2. Account status with system administrator"
            echo "  3. Jenkins SSH key configuration"
            currentBuild.result = 'UNSTABLE'
            return
          }
          echo "SSH connectivity to ${params.REMOTE_SSH} verified successfully"
        }
        
        // Use system SSH key of Jenkins user (passwordless access configured on server)
        sh label: 'Upload and publish', script: '''
          set -e
          DEST="${REMOTE_SSH}"
          REMOTE_REPO_DIR="${REMOTE_REPO_DIR}"
          COMPONENT="${COMPONENT}"
          DEB_DIST="${DEB_DIST:-}"

          echo "Creating incoming directory..."
          ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$DEST" "mkdir -p \"$REMOTE_REPO_DIR/incoming\"" || {
            echo "Failed to create incoming directory on remote server"
            exit 1
          }
          
          echo "Uploading .deb files..."
          for f in *.deb; do
            [ -e "$f" ] || continue
            echo "Uploading: $f"
            scp -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$f" "$DEST:$REMOTE_REPO_DIR/incoming/" || {
              echo "Failed to upload $f"
              exit 1
            }
          done
          
          echo "Processing packages with aptly..."
          # Add all uploaded packages to their respective distro repos using aptly
          DISTS=""
          for f in *.deb; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            dist="${base#*~}"; dist="${dist%%_*}"
            repo="${dist}-main-multiflexi"
            echo "Adding $base to repository: $repo"
            
            # Use -force-replace and -remove-files as recommended by aptly docs
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$DEST" "aptly repo add -force-replace -remove-files '$repo' '$REMOTE_REPO_DIR/incoming/$base'"; then
              echo "Successfully added $base to $repo"
            else
              echo "Warning: Failed to add $base to $repo (repository may not exist or aptly error)"
            fi
            
            case " $DISTS " in *" $dist "*) ;; *) DISTS="$DISTS $dist";; esac
            rm -f "$f"
          done
          
          echo "Package processing complete for distributions: $DISTS"
        '''
      }
    }
  }
}

