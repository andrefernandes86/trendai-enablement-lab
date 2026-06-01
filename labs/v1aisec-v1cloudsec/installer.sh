#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  TrendAI AI Security Lab — Installer                                    ║
# ║  Deploys the EKS lab stack and configures everything end-to-end.        ║
# ║                                                                          ║
# ║  Usage:                                                                  ║
# ║    ./installer.sh                        # interactive prompts           ║
# ║    ./installer.sh --name jdoe \          # fully scripted                ║
# ║      --api-key <key> --region us-east-1 ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
hdr()  { echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n  ${BOLD}$*${NC}\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/trendai-aisec-lab.yaml"
GHA_TEMPLATE="$SCRIPT_DIR/github-actions/v1-code-security.yml"

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║     TrendAI AI Security Lab — Installer                  ║"
echo "  ║     EKS + Container Security + GitHub Actions            ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Argument parsing ──────────────────────────────────────────────────────────
PARTICIPANT_NAME=""
V1_API_KEY=""
V1_REGION="us-east-1"
CS_TOKEN=""
GITHUB_REPO_FORK=""
NODE_TYPE="t3.xlarge"
SKIP_GHA=false
TEARDOWN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --name)              PARTICIPANT_NAME="$2"; shift 2 ;;
    --api-key)           V1_API_KEY="$2";       shift 2 ;;
    --region)            V1_REGION="$2";        shift 2 ;;
    --cs-token)          CS_TOKEN="$2";         shift 2 ;;
    --github-fork)       GITHUB_REPO_FORK="$2"; shift 2 ;;
    --node-type)         NODE_TYPE="$2";        shift 2 ;;
    --skip-github)       SKIP_GHA=true;         shift ;;
    --teardown)          TEARDOWN=true;         shift ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "  --name <name>          Participant name (used in stack/cluster names)"
      echo "  --api-key <key>        Vision One API key"
      echo "  --region <region>      Vision One region (default: us-east-1)"
      echo "  --cs-token <token>     Container Security bootstrap token (optional)"
      echo "  --github-fork <url>    GitHub fork URL for Code Security setup (optional)"
      echo "  --node-type <type>     EKS node type (default: t3.xlarge)"
      echo "  --skip-github          Skip GitHub Actions workflow setup"
      echo "  --teardown             Tear down the stack instead of deploying"
      exit 0 ;;
    *) err "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Teardown mode ─────────────────────────────────────────────────────────────
if $TEARDOWN; then
  hdr "Teardown"
  [ -z "$PARTICIPANT_NAME" ] && read -rp "  Participant name to tear down: " PARTICIPANT_NAME
  STACK_NAME="trendai-aisec-${PARTICIPANT_NAME}"
  warn "This will delete stack $STACK_NAME and all its resources."
  read -rp "  Type 'yes' to confirm: " CONFIRM
  [ "$CONFIRM" != "yes" ] && { info "Aborted."; exit 0; }
  info "Deleting CloudFormation stack $STACK_NAME..."
  aws cloudformation delete-stack --stack-name "$STACK_NAME"
  info "Waiting for stack deletion..."
  aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
  ok "Stack $STACK_NAME deleted."
  warn "Note: the NLB LoadBalancer created by the Kubernetes Service may persist."
  warn "Check EC2 > Load Balancers and delete manually if present."
  exit 0
fi

# ── Prerequisite checks ───────────────────────────────────────────────────────
hdr "Step 1 — Checking prerequisites"

check_tool() {
  local tool="$1" install_hint="$2"
  if command -v "$tool" &>/dev/null; then
    ok "$tool found ($(command -v "$tool"))"
  else
    err "$tool not found. $install_hint"
    MISSING=true
  fi
}

MISSING=false
check_tool aws     "Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
check_tool kubectl "Install: https://kubernetes.io/docs/tasks/tools/"
check_tool helm    "Install: https://helm.sh/docs/intro/install/"
check_tool git     "Install: https://git-scm.com/downloads"
check_tool jq      "Install: brew install jq  or  apt install jq"

if $MISSING; then
  err "Install missing tools above and re-run."
  exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  err "AWS credentials not configured. Run: aws configure"
  exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
ok "AWS account: $AWS_ACCOUNT  |  region: $AWS_REGION"

# Check CFN template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
  err "CloudFormation template not found at: $TEMPLATE_FILE"
  err "Run this script from inside the labs/v1aisec-v1cloudsec/ directory, or pass the full path."
  exit 1
fi

# ── Collect parameters ────────────────────────────────────────────────────────
hdr "Step 2 — Parameters"

if [ -z "$PARTICIPANT_NAME" ]; then
  read -rp "  Participant name (e.g. jdoe): " PARTICIPANT_NAME
fi
[ -z "$PARTICIPANT_NAME" ] && { err "Participant name is required."; exit 1; }

if [ -z "$V1_API_KEY" ]; then
  read -rsp "  Vision One API key: " V1_API_KEY; echo
fi
[ -z "$V1_API_KEY" ] && { err "V1 API key is required."; exit 1; }

echo "  Vision One region [$V1_REGION]: "
read -rp "  (press Enter to keep default): " INPUT_REGION
[ -n "$INPUT_REGION" ] && V1_REGION="$INPUT_REGION"

if [ -z "$CS_TOKEN" ]; then
  echo ""
  info "Container Security bootstrap token (optional)."
  info "Get from: Vision One > Container Security > Clusters > Add Cluster > Copy Token"
  info "Leave blank to install Container Security manually later."
  read -rsp "  Bootstrap token (or Enter to skip): " CS_TOKEN; echo
fi

if ! $SKIP_GHA && [ -z "$GITHUB_REPO_FORK" ]; then
  echo ""
  info "GitHub fork URL for Code Security setup (optional)."
  info "Example: https://github.com/yourname/demo-v1-app-sec-file-sec"
  info "Leave blank to skip GitHub Actions setup."
  read -rp "  Fork URL (or Enter to skip): " GITHUB_REPO_FORK
  [ -z "$GITHUB_REPO_FORK" ] && SKIP_GHA=true
fi

STACK_NAME="trendai-aisec-${PARTICIPANT_NAME}"
CLUSTER_NAME="trendai-aisec-${PARTICIPANT_NAME}"

echo ""
echo -e "  ${BOLD}Stack name  :${NC} $STACK_NAME"
echo -e "  ${BOLD}Cluster name:${NC} $CLUSTER_NAME"
echo -e "  ${BOLD}V1 region   :${NC} $V1_REGION"
echo -e "  ${BOLD}Node type   :${NC} $NODE_TYPE"
echo -e "  ${BOLD}CS token    :${NC} ${CS_TOKEN:+(provided)}${CS_TOKEN:-not provided}"
echo -e "  ${BOLD}GitHub fork :${NC} ${GITHUB_REPO_FORK:-(skipped)}"
echo ""
read -rp "  Proceed? [Y/n]: " CONFIRM
[[ "${CONFIRM:-Y}" =~ ^[Nn] ]] && { info "Aborted."; exit 0; }

# ── Deploy CloudFormation stack ───────────────────────────────────────────────
hdr "Step 3 — Deploying CloudFormation stack"

info "Submitting stack: $STACK_NAME"

PARAMS=(
  "ParameterKey=ParticipantName,ParameterValue=${PARTICIPANT_NAME}"
  "ParameterKey=V1ApiKey,ParameterValue=${V1_API_KEY}"
  "ParameterKey=V1Region,ParameterValue=${V1_REGION}"
  "ParameterKey=NodeInstanceType,ParameterValue=${NODE_TYPE}"
)

[ -n "$CS_TOKEN" ] && PARAMS+=("ParameterKey=ContainerSecurityToken,ParameterValue=${CS_TOKEN}")

aws cloudformation create-stack \
  --stack-name "$STACK_NAME" \
  --template-body "file://${TEMPLATE_FILE}" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameters "${PARAMS[@]}" \
  --tags Key=Lab,Value=trendai-aisec Key=Participant,Value="${PARTICIPANT_NAME}" \
  2>/dev/null || {
    # Stack may already exist — try update
    warn "Stack already exists — attempting update..."
    aws cloudformation update-stack \
      --stack-name "$STACK_NAME" \
      --template-body "file://${TEMPLATE_FILE}" \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      --parameters "${PARAMS[@]}" 2>/dev/null || {
        info "No changes to apply or stack is already up to date."
      }
  }

info "Waiting for EKS cluster and stack to be ready (~20 minutes)..."
echo "  (You can watch progress in the AWS Console > CloudFormation > $STACK_NAME)"
echo ""

# Show a simple spinner while waiting
SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPIN_IDX=0
WAIT_START=$(date +%s)

while true; do
  STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "PENDING")

  ELAPSED=$(( $(date +%s) - WAIT_START ))
  MINS=$(( ELAPSED / 60 ))
  SECS=$(( ELAPSED % 60 ))

  printf "\r  %s  Status: %-30s  Elapsed: %02dm%02ds" \
    "${SPIN:$SPIN_IDX:1}" "$STATUS" "$MINS" "$SECS"
  SPIN_IDX=$(( (SPIN_IDX + 1) % ${#SPIN} ))

  case "$STATUS" in
    CREATE_COMPLETE|UPDATE_COMPLETE)
      echo ""; ok "Stack $STACK_NAME is ready."; break ;;
    CREATE_FAILED|ROLLBACK_COMPLETE|ROLLBACK_FAILED|UPDATE_ROLLBACK_COMPLETE)
      echo ""
      err "Stack deployment failed with status: $STATUS"
      err "Check CloudFormation Events for details:"
      aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
        --output table 2>/dev/null || true
      exit 1 ;;
    DELETE_IN_PROGRESS|DELETE_COMPLETE)
      echo ""; err "Stack is being deleted. Aborting."; exit 1 ;;
  esac
  sleep 3
done

# ── Read outputs ──────────────────────────────────────────────────────────────
hdr "Step 4 — Reading stack outputs"

get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text 2>/dev/null || echo ""
}

BOOTSTRAP_INSTANCE_ID=$(get_output "BootstrapInstanceId")
SSM_CONNECT=$(get_output "SsmConnectCommand")
KUBECONFIG_CMD=$(get_output "KubeconfigCommand")

ok "Bootstrap instance ID : $BOOTSTRAP_INSTANCE_ID"
ok "Kubeconfig command    : $KUBECONFIG_CMD"

# ── Configure local kubectl ───────────────────────────────────────────────────
hdr "Step 5 — Configuring local kubectl"

info "Running: $KUBECONFIG_CMD"
eval "$KUBECONFIG_CMD"
ok "kubeconfig updated. Context: $(kubectl config current-context 2>/dev/null)"

# ── Wait for nodes and pods ───────────────────────────────────────────────────
hdr "Step 6 — Waiting for Kubernetes nodes and pods"

info "Waiting for EKS nodes to be Ready..."
for i in $(seq 1 30); do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || echo 0)
  if [ "$READY_NODES" -ge 1 ]; then
    ok "$READY_NODES node(s) ready."
    break
  fi
  printf "\r  attempt %d/30 — no ready nodes yet, waiting 15s..." "$i"
  sleep 15
done
echo ""
kubectl get nodes

info "Waiting for trendai-lab pods to be Running..."
for i in $(seq 1 40); do
  RUNNING=$(kubectl get pods -n trendai-lab --no-headers 2>/dev/null \
    | grep -c 'Running' || echo 0)
  TOTAL=$(kubectl get pods -n trendai-lab --no-headers 2>/dev/null \
    | wc -l | tr -d ' ' || echo 0)
  printf "\r  %d/%d pods running (attempt %d/40, waiting 15s)..." "$RUNNING" "$TOTAL" "$i"
  [ "$RUNNING" -ge 2 ] && { echo ""; ok "App pods are running."; break; }
  sleep 15
done
echo ""
kubectl get pods -n trendai-lab

# ── Container Security ────────────────────────────────────────────────────────
hdr "Step 7 — Container Security"

CS_PODS=$(kubectl get pods -n trendmicro-system --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo 0)
if [ "$CS_PODS" -gt 0 ]; then
  ok "Container Security pods detected ($CS_PODS pods in trendmicro-system)."
  kubectl get pods -n trendmicro-system
elif [ -n "$CS_TOKEN" ]; then
  warn "Container Security not yet installed — running Helm install now..."

  kubectl create namespace trendmicro-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace trendmicro-system \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite

  CS_OVERRIDES_TMP=$(mktemp /tmp/cs-overrides-XXXX.yaml)
  cat > "$CS_OVERRIDES_TMP" <<CSEOF
visionOne:
  bootstrapToken: "${CS_TOKEN}"
runtimeSecurity:
  enabled: true
admissionController:
  enabled: true
oversight:
  enabled: true
CSEOF

  helm install \
    --values "$CS_OVERRIDES_TMP" \
    --namespace trendmicro-system \
    --create-namespace \
    trendmicro \
    https://github.com/trendmicro/visionone-container-security-helm/archive/main.tar.gz

  rm -f "$CS_OVERRIDES_TMP"
  ok "Container Security Helm chart installed."
  info "Waiting for Container Security pods..."
  kubectl rollout status daemonset -n trendmicro-system --timeout=120s 2>/dev/null || true
  kubectl get pods -n trendmicro-system
else
  warn "Container Security not installed (no token provided)."
  warn "To install manually, run:"
  warn "  helm install --values k8s/container-security-overrides.yaml \\"
  warn "    --namespace trendmicro-system --create-namespace trendmicro \\"
  warn "    https://github.com/trendmicro/visionone-container-security-helm/archive/main.tar.gz"
fi

# ── GitHub Actions ────────────────────────────────────────────────────────────
if ! $SKIP_GHA && [ -n "$GITHUB_REPO_FORK" ]; then
  hdr "Step 8 — GitHub Actions: Code Security workflow"

  CLONE_DIR=$(mktemp -d /tmp/demo-repo-XXXX)
  info "Cloning fork: $GITHUB_REPO_FORK → $CLONE_DIR"

  if git clone --depth 1 "$GITHUB_REPO_FORK" "$CLONE_DIR" 2>/dev/null; then
    # Create the workflow directory and copy the file
    mkdir -p "$CLONE_DIR/.github/workflows"

    if [ -f "$GHA_TEMPLATE" ]; then
      cp "$GHA_TEMPLATE" "$CLONE_DIR/.github/workflows/v1-code-security.yml"
      ok "Workflow file copied to .github/workflows/v1-code-security.yml"
    else
      warn "GitHub Actions template not found at $GHA_TEMPLATE — writing inline..."
      cat > "$CLONE_DIR/.github/workflows/v1-code-security.yml" <<'GHAEOF'
name: Vision One Code Security
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
  pull-requests: write
jobs:
  v1-code-scan:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
        with:
          path: repo
      - uses: trendmicro/tmas-scan-action@v2
        with:
          version: '2'
          vulnerabilitiesScan: true
          secretsScan: true
          malwareScan: true
          artifact: dir:./repo
          additionalArgs: --region=us-east-1
          tmasApiKey: ${{ secrets.TMAS_API_KEY }}
          githubToken: ${{ secrets.GITHUB_TOKEN }}
GHAEOF
    fi

    # Commit and push
    cd "$CLONE_DIR"
    if git diff --quiet HEAD 2>/dev/null && git status --porcelain | grep -q "workflows"; then
      git config user.email "lab-installer@trendai.lab"
      git config user.name "TrendAI Lab Installer"
      git add .github/workflows/v1-code-security.yml
      git commit -m "ci: add Vision One Code Security GitHub Actions workflow"
      git push origin HEAD
      ok "Workflow pushed to fork."
      echo ""
      warn "ACTION REQUIRED — add the TMAS_API_KEY secret to the repo:"
      warn "  1. Open: $GITHUB_REPO_FORK/settings/secrets/actions"
      warn "  2. Click 'New repository secret'"
      warn "  3. Name: TMAS_API_KEY"
      warn "  4. Value: (your Vision One API key — same as V1ApiKey above)"
    else
      ok "Workflow file already present or no changes needed."
    fi

    cd "$SCRIPT_DIR"
    rm -rf "$CLONE_DIR"
  else
    warn "Could not clone $GITHUB_REPO_FORK — skipping GitHub Actions setup."
    warn "Add the workflow manually: copy github-actions/v1-code-security.yml"
    warn "to .github/workflows/ in your fork and push."
  fi
else
  info "GitHub Actions setup skipped."
fi

# ── Get app URL ───────────────────────────────────────────────────────────────
hdr "Step ${SKIP_GHA:+8}${SKIP_GHA:-9} — App URL"

info "Waiting for LoadBalancer hostname..."
APP_URL=""
for i in $(seq 1 20); do
  LB=$(kubectl get svc trendai-app -n trendai-lab \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$LB" ]; then
    APP_URL="http://$LB:8000"
    ok "App URL: $APP_URL"
    break
  fi
  printf "\r  waiting for NLB hostname (attempt %d/20, 15s)..." "$i"
  sleep 15
done
echo ""

if [ -z "$APP_URL" ]; then
  warn "LoadBalancer hostname not yet assigned. Check later with:"
  warn "  kubectl get svc trendai-app -n trendai-lab"
fi

# Wait for app to respond
if [ -n "$APP_URL" ]; then
  info "Waiting for app to respond at $APP_URL..."
  for i in $(seq 1 20); do
    if curl -sf --max-time 5 "$APP_URL/" >/dev/null 2>&1; then
      ok "App is responding!"; break
    fi
    printf "\r  attempt %d/20 (NLB DNS may need up to 2 min to propagate)..." "$i"
    sleep 10
  done
  echo ""
fi

# ── Summary ───────────────────────────────────────────────────────────────────
hdr "🎉  Deployment complete"

echo ""
echo -e "  ${BOLD}Stack name      :${NC} $STACK_NAME"
echo -e "  ${BOLD}EKS cluster     :${NC} $CLUSTER_NAME"
echo -e "  ${BOLD}App URL         :${NC} ${APP_URL:-run: kubectl get svc trendai-app -n trendai-lab}"
echo -e "  ${BOLD}Bootstrap EC2   :${NC} $BOOTSTRAP_INSTANCE_ID"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo ""
echo "    # Connect to bootstrap EC2 (kubectl + helper scripts pre-configured)"
echo "    $SSM_CONNECT"
echo ""
echo "    # Run AI Scanner (from bootstrap EC2)"
echo "    aws ssm start-session --target $BOOTSTRAP_INSTANCE_ID \\"
echo "      --document-name AWS-StartInteractiveCommand \\"
echo "      --parameters command='ai-scan'"
echo ""
echo "    # Run container attack simulation (from bootstrap EC2)"
echo "    aws ssm start-session --target $BOOTSTRAP_INSTANCE_ID \\"
echo "      --document-name AWS-StartInteractiveCommand \\"
echo "      --parameters command='cs-attack'"
echo ""
echo "    # Watch pods"
echo "    kubectl get pods -n trendai-lab -w"
echo ""
echo "    # Tear down"
echo "    $0 --teardown --name $PARTICIPANT_NAME"
echo ""

if [ -z "$CS_TOKEN" ]; then
  echo -e "  ${YELLOW}${BOLD}Next step — Container Security:${NC}"
  echo "  Get a bootstrap token from Vision One > Container Security > Clusters > Add Cluster"
  echo "  Then run the Helm install from k8s/container-security-overrides.yaml"
  echo ""
fi

if $SKIP_GHA; then
  echo -e "  ${YELLOW}${BOLD}Next step — Code Security:${NC}"
  echo "  Copy github-actions/v1-code-security.yml to .github/workflows/ in your demo repo fork"
  echo "  Add TMAS_API_KEY as a GitHub Actions secret"
  echo ""
fi
