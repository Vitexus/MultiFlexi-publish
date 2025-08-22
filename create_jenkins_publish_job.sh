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


# Read Jenkinsfile content
JENKINSFILE_PATH="$(dirname "$0")/Jenkinsfile"
if [[ ! -f "$JENKINSFILE_PATH" ]]; then
  die "Jenkinsfile not found at $JENKINSFILE_PATH"
fi
JENKINSFILE_CONTENT=$(<"$JENKINSFILE_PATH")

# Create config.xml using Jenkinsfile content
cat > "$CONFIG_XML" <<EOF
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
          <defaultValue>${JENKINS_URL}</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>UPSTREAM_JOB</name>
          <description>Upstream job name inside ${JENKINS_FOLDER}</description>
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

