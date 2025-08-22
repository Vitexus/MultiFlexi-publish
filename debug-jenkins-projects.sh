#!/usr/bin/env bash
set -euo pipefail

# Debug script to discover Jenkins projects
# Usage: ./debug-jenkins-projects.sh [search_pattern]

if [ -z "${JENKINS_URL:-}" ] || [ -z "${JENKINS_USER:-}" ] || [ -z "${JENKINS_TOKEN:-}" ]; then
    echo "ERROR: Missing required environment variables:"
    echo "  JENKINS_URL, JENKINS_USER, JENKINS_TOKEN"
    echo ""
    echo "Set them like this:"
    echo "  export JENKINS_URL='https://jenkins.proxy.spojenet.cz'"
    echo "  export JENKINS_USER='your-username'"
    echo "  export JENKINS_TOKEN='your-api-token'"
    exit 1
fi

SEARCH_PATTERN="${1:-}"

echo "Discovering Jenkins projects..."
echo "Jenkins URL: $JENKINS_URL"
echo "Search pattern: ${SEARCH_PATTERN:-'(all projects)'}"
echo ""

# Function to make authenticated Jenkins API calls
jenkins_api() {
    local path="$1"
    curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" "$JENKINS_URL$path"
}

echo "=== Top-level jobs ==="
jenkins_api "/api/json?tree=jobs[name,_class]" | jq -r '.jobs[] | select(._class == "com.cloudbees.hudson.plugins.folder.Folder" or ._class == "hudson.model.FreeStyleProject" or ._class == "org.jenkinsci.plugins.workflow.job.WorkflowJob") | .name' | sort

echo ""
echo "=== MultiFlexi folder contents ==="
if jenkins_api "/job/MultiFlexi/api/json?tree=jobs[name,_class]" 2>/dev/null | jq -r '.jobs[]? | .name' | sort; then
    echo "Found MultiFlexi folder with jobs above"
else
    echo "MultiFlexi folder not found or empty"
fi

echo ""
if [ -n "$SEARCH_PATTERN" ]; then
    echo "=== Projects matching '$SEARCH_PATTERN' ==="
    # Search in top-level
    jenkins_api "/api/json?tree=jobs[name,_class]" | jq -r --arg pattern "$SEARCH_PATTERN" '.jobs[] | select(.name | test($pattern; "i")) | .name' | sort
    
    # Search in MultiFlexi folder
    jenkins_api "/job/MultiFlexi/api/json?tree=jobs[name,_class]" 2>/dev/null | jq -r --arg pattern "$SEARCH_PATTERN" '.jobs[]? | select(.name | test($pattern; "i")) | .name' | sort || true
fi

echo ""
echo "=== Recent builds in MultiFlexi folder ==="
jenkins_api "/job/MultiFlexi/api/json?tree=jobs[name,lastBuild[number,result]]" 2>/dev/null | jq -r '.jobs[]? | select(.lastBuild) | "\(.name): #\(.lastBuild.number) (\(.lastBuild.result // "RUNNING"))"' | sort || echo "No builds found or folder not accessible"
