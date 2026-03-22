#!/usr/bin/env bash
# Generate an OOD cluster YAML from a running ParallelCluster cluster.
# Output goes to /etc/ood/config/clusters.d/<cluster-name>.yml
#
# Usage:
#   ./gen-cluster-yaml.sh <cluster-name> [--region us-east-1]
set -euo pipefail

CLUSTER_NAME="${1:-}"
REGION="${AWS_REGION:-us-east-1}"
OUTPUT_DIR="/etc/ood/config/clusters.d"

if [ -z "${CLUSTER_NAME}" ]; then
  echo "Usage: $0 <cluster-name> [--region REGION]" >&2
  exit 1
fi

for arg in "$@"; do
  case "${arg}" in
    --region=*) REGION="${arg#*=}" ;;
  esac
done

# Get head node IP from ParallelCluster describe-cluster
HEAD_NODE_IP=$(aws pcluster describe-cluster \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'headNode.publicIpAddress // headNode.privateIpAddress' \
  --output text 2>/dev/null || echo "")

if [ -z "${HEAD_NODE_IP}" ]; then
  echo "ERROR: Could not find head node IP for cluster ${CLUSTER_NAME}" >&2
  exit 1
fi

# Get SLURM partitions
PARTITIONS=$(aws pcluster describe-cluster \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'clusterConfiguration' \
  --output text 2>/dev/null | python3 -c "
import sys, yaml
cfg = yaml.safe_load(sys.stdin)
queues = cfg.get('Scheduling', {}).get('SlurmQueues', [])
for q in queues:
    print(q['Name'])
" 2>/dev/null || echo "all")

mkdir -p "${OUTPUT_DIR}"

cat > "${OUTPUT_DIR}/${CLUSTER_NAME}.yml" <<CLUSTERCONF
---
v2:
  metadata:
    title: "ParallelCluster: ${CLUSTER_NAME}"
    hidden: false
  login:
    host: "${HEAD_NODE_IP}"
  job:
    adapter: "slurm"
    submit_host: "${HEAD_NODE_IP}"
    bin: "/opt/slurm/bin"
    conf: "/opt/slurm/etc/slurm.conf"
    bin_overrides:
      sbatch: "%{OOD_PORTAL_DIR}/bin/slurm/sbatch"
CLUSTERCONF

echo "==> Generated ${OUTPUT_DIR}/${CLUSTER_NAME}.yml"
echo "    Head node: ${HEAD_NODE_IP}"
echo "    Reload OOD: /opt/ood/ood-portal-generator/sbin/update_ood_portal && systemctl reload nginx"
