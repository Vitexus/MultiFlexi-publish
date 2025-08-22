#!/usr/bin/env bash
set -euo pipefail

# create_jenkins_publish_job.sh (retryable)
# Same content as before, but avoid here-doc in variable due to bash -e -u -o pipefail in some shells.

JENKINS_FOLDER=${JENKINS_FOLDER:-MultiFlexi}
PUBLISH_CREDENTIALS_ID=${PUBLISH_CREDENTIALS_ID:-repo-ssh}

err() { echo "[ERROR] $*" >&2; }
log() { echo "[INFO]  $*" >&2; }
die() { err "$*"; exit 1; }

for v in JENKINS_URL JENKINS_USER JENKINS_TOKEN; do
  [[ -n "${!v:-}" ]] || die "Missing required env: $v"
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
CONFIG_XML="$TMPDIR/config.xml"

cat > "$CONFIG_XML" <<'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Publishes .deb artifacts from MultiFlexi upstream builds to repo.multiflexi.eu</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>JENKINS_URL</name>
          <description>Jenkins base URL</description>
          <defaultValue>__JENKINS_URL__</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>UPSTREAM_JOB</name>
          <description>Upstream job name inside __JENKINS_FOLDER__</description>
          <defaultValue></defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>UPSTREAM_BUILD</name>
          <description>Upstream build number</description>
          <defaultValue></defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>REMOTE_SSH</name>
          <description>SSH user@host of repository server</description>
<defaultValue>multirepo@repo.multiflexi.eu</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>REMOTE_REPO_DIR</name>
          <description>Repository base directory</description>
          <defaultValue>/srv/repo</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>COMPONENT</name>
          <description>Repository component</description>
          <defaultValue>main</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>DEB_DIST</name>
          <description>Debian/Ubuntu distributions (space or comma separated), can be empty</description>
          <defaultValue></defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
<script><![CDATA[
import groovy.json.JsonSlurperClassic

pipeline {
  agent any
parameters {
    string(name: 'JENKINS_URL', defaultValue: '__JENKINS_URL__', description: 'Jenkins base URL')
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
          copyArtifacts projectName: projectPath, selector: specific(buildNum), filter: '**/*.deb', flatten: true, optional: true
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
# Add each uploaded package into its distro repo with aptly, then remove it remotely and locally
          DISTS=""
          for f in *.deb; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            dist="${base#*~}"; dist="${dist%%_*}"
            repo="${dist}-main-multiflexi"
            ssh -o StrictHostKeyChecking=no "$DEST" "aptly repo add -force-replace '$repo' '$REMOTE_REPO_DIR/incoming/$base' && rm -f '$REMOTE_REPO_DIR/incoming/$base'" || true
            case " $DISTS " in *" $dist "*) ;; *) DISTS="$DISTS $dist";; esac
            rm -f "$f"
          done

          # For each touched distribution, create snapshot and publish update
          for dist in $DISTS; do
            repo="${dist}-main-multiflexi"
            ssh -o StrictHostKeyChecking=no "$DEST" "repo='$repo'; SNAP=\"\${repo}-\$(date +%Y%m%d%H%M%S)\"; aptly snapshot create \"\$SNAP\" from repo \"\$repo\"; aptly publish update '$dist' || aptly publish snapshot \"\$SNAP\" ." || true
          done
        '''
      }
    }
  }
}
    ]]></script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

# Substitute placeholders
sed -i "s#__JENKINS_URL__#${JENKINS_URL//\/\\/}#g; s#__JENKINS_FOLDER__#${JENKINS_FOLDER}#g; s#__CREDENTIALS_ID__#${PUBLISH_CREDENTIALS_ID}#g" "$CONFIG_XML"

jenkins_api() {
  local method=$1 url=$2 file=${3:-}
  local crumb="" field="Jenkins-Crumb"
  local cj
  cj=$(curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL/crumbIssuer/api/json" || true)
  if [[ -n "$cj" ]]; then
    crumb=$(echo "$cj" | sed -n 's/.*"crumb"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    field=$(echo "$cj" | sed -n 's/.*"crumbRequestField"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  fi
  if [[ -n "$file" ]]; then
    curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" -H "${field}: ${crumb}" -H 'Content-Type: application/xml' -X "$method" --data-binary @"$file" "$url"
  else
    curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" -H "${field}: ${crumb}" -X "$method" "$url"
  fi
}

JOB_API_BASE="$JENKINS_URL/job/$JENKINS_FOLDER/job/MultiFlexi-publish"
log "Ensuring job exists: $JOB_API_BASE"
if jenkins_api GET "$JOB_API_BASE/api/json" >/dev/null 2>&1; then
  log "Job exists; updating config"
  jenkins_api POST "$JOB_API_BASE/config.xml" "$CONFIG_XML" || die "Failed to update job config"
else
  log "Creating job"
  jenkins_api POST "$JENKINS_URL/job/$JENKINS_FOLDER/createItem?name=MultiFlexi-publish" "$CONFIG_XML" || die "Failed to create job"
fi

log "MultiFlexi-publish is ready: $JOB_API_BASE"

