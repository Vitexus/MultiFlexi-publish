
import groovy.json.JsonSlurperClassic

pipeline {
  agent any
parameters {
    string(name: 'JENKINS_URL', defaultValue: 'https://jenkins.proxy.spojenet.cz', description: 'Jenkins base URL')
    string(name: 'JENKINS_USER', defaultValue: '', description: 'Jenkins API user (optional, for auto-fix)')
    string(name: 'JENKINS_TOKEN', defaultValue: '', description: 'Jenkins API token (optional, for auto-fix)')
    booleanParam(name: 'AUTO_FIX_COPY_PERMISSION', defaultValue: true, description: 'Auto-fix Copy Artifact permission on upstream when credentials provided')
    string(name: 'UPSTREAM_JOB', defaultValue: '', description: 'Upstream job name or full path (e.g., composer-debian or MultiFlexi/composer-debian)')
    string(name: 'UPSTREAM_BUILD', defaultValue: '', description: 'Upstream build number')
    string(name: 'REMOTE_SSH', defaultValue: 'multirepo@repo.multiflexi.eu', description: 'SSH user@host of repository server')
    string(name: 'REMOTE_REPO_DIR', defaultValue: '/srv/repo', description: 'Repository base directory')
    string(name: 'COMPONENT', defaultValue: 'main', description: 'Repository component')
    string(name: 'DEB_DIST', defaultValue: '', description: 'Debian/Ubuntu distributions (space or comma separated), can be empty')
  }
  options { timestamps() }
  stages {
    stage('Ensure upstream Copy Artifact permission') {
      when {
        expression { return params.AUTO_FIX_COPY_PERMISSION && params.JENKINS_USER?.trim() && params.JENKINS_TOKEN?.trim() }
      }
      steps {
        script {
          // Determine upstream job/build from UpstreamCause or fallback to params
          def upJob = params.UPSTREAM_JOB?.trim()
          def upBuild = params.UPSTREAM_BUILD?.trim()
          def cause = currentBuild.rawBuild?.getCause(hudson.model.Cause$UpstreamCause)
          if (!upJob && cause) { upJob = cause.upstreamProject }
          if (!upBuild && cause) { upBuild = (cause.upstreamBuild as String) }
          if (!upJob) { error('Unable to determine upstream job name') }
          def projectPath = upJob.contains('/') ? upJob : "MultiFlexi/${upJob}"
          def projectPathJob = projectPath.split('/').collect{ "job/${it}" }.join('/')
          def configUrl = "${params.JENKINS_URL}/${projectPathJob}/config.xml"
          def currentJobFullName = env.JOB_NAME
          withEnv([
            "JENKINS_URL=${params.JENKINS_URL}",
            "CONFIG_URL=${configUrl}",
            "JENKINS_USER=${params.JENKINS_USER}",
            "JENKINS_TOKEN=${params.JENKINS_TOKEN}",
            "JOB_FULL_NAME=${currentJobFullName}"
          ]) {
            sh label: 'Ensure Copy Artifact permission on upstream', script: '''
              set -e
              CRUMB_JSON=$(curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/crumbIssuer/api/json" || true)
              CRUMB=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumb"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
              CRUMB_FIELD=$(echo "$CRUMB_JSON" | sed -n 's/.*"crumbRequestField"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

              TMP=$(mktemp)
              curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" "$CONFIG_URL" > "$TMP" || true

              if grep -q "CopyArtifactPermissionProperty" "$TMP"; then
                if grep -q "<string>$JOB_FULL_NAME</string>" "$TMP"; then
                  echo "CopyArtifact permission already present for $JOB_FULL_NAME"
                  rm -f "$TMP"
                  exit 0
                fi
                awk -v job="$JOB_FULL_NAME" '
                  {print}
                  /<projectNameList>/ {inlist=1}
                  inlist && /<\/projectNameList>/ {print "    <string>"job"</string>"; inlist=0}
                ' "$TMP" > "$TMP.new"
              else
                awk -v job="$JOB_FULL_NAME" '
                  BEGIN{inserted=0}
                  {
                    print
                    if(!inserted && $0 ~ /<properties>/){
                      print "    <hudson.plugins.copyartifact.CopyArtifactPermissionProperty>"
                      print "      <projectNameList>"
                      print "        <string>" job "</string>"
                      print "      </projectNameList>"
                      print "    </hudson.plugins.copyartifact.CopyArtifactPermissionProperty>"
                      inserted=1
                    }
                  }
                ' "$TMP" > "$TMP.new"
              fi

              if cmp -s "$TMP" "$TMP.new"; then
                echo "No changes required to config.xml"
                rm -f "$TMP" "$TMP.new"
                exit 0
              fi

              if [ -n "$CRUMB" ] && [ -n "$CRUMB_FIELD" ]; then
                curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" -H "$CRUMB_FIELD: $CRUMB" -H 'Content-Type: application/xml' -X POST --data-binary @"$TMP.new" "$CONFIG_URL"
              else
                curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" -H 'Content-Type: application/xml' -X POST --data-binary @"$TMP.new" "$CONFIG_URL"
              fi
              echo "Upstream config.xml updated to allow Copy Artifact from $JOB_FULL_NAME"
              rm -f "$TMP" "$TMP.new"
            '''
          }
        }
        }
      }
    }
stage('Fetch artifacts') {
      steps {
        // Clean previous .deb files from workspace to avoid re-uploading old builds
        sh 'rm -f *.deb 2>/dev/null || true'
        script {
          // Determine upstream job/build from UpstreamCause or fallback to params
          def upJob = params.UPSTREAM_JOB?.trim()
          def upBuild = params.UPSTREAM_BUILD?.trim()
          def cause = currentBuild.rawBuild?.getCause(hudson.model.Cause$UpstreamCause)
          if (!upJob && cause) { upJob = cause.upstreamProject }
          if (!upBuild && cause) { upBuild = (cause.upstreamBuild as String) }
          if (!upJob || !upBuild) { error('Unable to determine upstream job and build') }
          def projectPath = upJob.contains('/') ? upJob : "MultiFlexi/${upJob}"
          // Copy Artifact plugin often requires '/job/.../job/...' style for foldered jobs
          def projectPathCA = "/job/${projectPath.replace('/', '/job/')}"
          echo "Copying .deb artifacts from ${projectPath} (#${upBuild})"
          echo "Resolved Copy Artifact path: ${projectPathCA}"
          
          // Try multiple approaches to get artifacts
          def copySuccess = false
          
          // Method 1: Direct project path using '/job/..' style
          try {
            copyArtifacts projectName: projectPathCA, selector: specific(upBuild), filter: '**/dist/debian/*.deb, **/*.deb', flatten: true, optional: true
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
                copyArtifacts projectName: simpleJobCA, selector: specific(upBuild), filter: '**/dist/debian/*.deb, **/*.deb', flatten: true, optional: true
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
          
          // Method 4: HTTP download via Jenkins API (requires JENKINS_USER/TOKEN)
          if (!copySuccess && params.JENKINS_USER?.trim() && params.JENKINS_TOKEN?.trim() && params.JENKINS_URL?.trim()) {
            echo "Attempting HTTP download of artifacts via Jenkins API..."
            withEnv([
              "JENKINS_URL=${params.JENKINS_URL}",
              "JENKINS_USER=${params.JENKINS_USER}",
              "JENKINS_TOKEN=${params.JENKINS_TOKEN}",
              "UPSTREAM=${projectPath}",
              "BUILD=${upBuild}"
            ]) {
              def httpStatus = sh(returnStatus: true, label: 'HTTP download .deb artifacts', script: '''
                set -e
                JOB_PATH=$(awk -v p="$UPSTREAM" 'BEGIN{n=split(p,a,"/"); for(i=1;i<=n;i++) printf "/job/%s", a[i]}')
                JSON_URL="$JENKINS_URL$JOB_PATH/$BUILD/api/json?tree=artifacts[fileName,relativePath]"

                if command -v jq >/dev/null 2>&1; then
                  rels=$(curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" "$JSON_URL" | jq -r '.artifacts[] | select(.fileName|endswith(".deb")) | .relativePath' || true)
                  if [ -n "$rels" ]; then
                    echo "$rels" | while IFS= read -r rel; do
                      echo "Downloading: $rel"
                      curl -sfL -u "$JENKINS_USER:$JENKINS_TOKEN" -o "$(basename "$rel")" "$JENKINS_URL$JOB_PATH/$BUILD/artifact/$rel"
                    done
                  else
                    echo "No .deb artifacts listed by Jenkins API JSON"
                  fi
                else
                  echo "jq not found; falling back to ZIP download of dist/debian"
                  curl -sfL -u "$JENKINS_USER:$JENKINS_TOKEN" -o debian.zip "$JENKINS_URL$JOB_PATH/$BUILD/artifact/dist/debian/*zip*/debian.zip" || true
                  if [ -s debian.zip ]; then
                    unzip -o debian.zip >/dev/null
                    # move any extracted debs into workspace root
                    find . -maxdepth 3 -type f -name '*.deb' -exec sh -c 'for f; do base=$(basename "$f"); [ -f "$base" ] || cp -f "$f" ./; done' sh {} +
                    rm -f debian.zip
                  else
                    echo "ZIP download not available"
                  fi
                fi
              ''')
            }
            def hasHttpDebs = sh(returnStatus: true, script: 'ls -1 *.deb >/dev/null 2>&1') == 0
            if (hasHttpDebs) {
              copySuccess = true
              echo 'Downloaded .deb artifacts via Jenkins API successfully'
            } else {
              echo 'HTTP download did not retrieve any .deb artifacts'
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

