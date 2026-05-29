#!/usr/bin/env bash
# Install oidc-pam NSS/PAM modules on a ParallelCluster head node.
# Called by OnNodeConfigured in cluster-config.yaml.
#
# Args:
#   --oidc-issuer=URL       OIDC issuer URL (Cognito User Pool endpoint)
#   --dynamodb-table=NAME   DynamoDB UID mapping table name
#   --efs-id=ID             EFS file system ID (optional, for /home mount)
set -euo pipefail

OIDC_ISSUER=""
DYNAMODB_TABLE=""
EFS_ID=""

for arg in "$@"; do
  case "${arg}" in
    --oidc-issuer=*)    OIDC_ISSUER="${arg#*=}" ;;
    --dynamodb-table=*) DYNAMODB_TABLE="${arg#*=}" ;;
    --efs-id=*)         EFS_ID="${arg#*=}" ;;
  esac
done

REGION=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" | \
  xargs -I{} curl -s -H "X-aws-ec2-metadata-token: {}" \
  "http://169.254.169.254/latest/meta-data/placement/region")

echo "=== Setting up oidc-pam on head node ==="
echo "  OIDC issuer    : ${OIDC_ISSUER}"
echo "  DynamoDB table : ${DYNAMODB_TABLE}"
echo "  Region         : ${REGION}"
echo "  EFS id         : ${EFS_ID:-<none>}"

# Mount shared EFS home if an --efs-id was supplied. oidc-pam provisions user
# homes under /home (home_dir_prefix in broker.yaml below), so /home must be the
# shared EFS mount for UIDs to see consistent home directories across nodes.
if [ -n "${EFS_ID}" ]; then
  echo "Mounting EFS ${EFS_ID} at /home"
  command -v mount.efs >/dev/null 2>&1 || yum install -y amazon-efs-utils 2>/dev/null || true
  if ! mountpoint -q /home; then
    mount -t efs -o tls "${EFS_ID}":/ /home
    grep -q "${EFS_ID}:/ /home" /etc/fstab || echo "${EFS_ID}:/ /home efs _netdev,tls 0 0" >> /etc/fstab
  fi
fi

# Install oidc-pam from latest GitHub release
ARCH=$(uname -m)
OIDC_PAM_ARCH="amd64"
[ "${ARCH}" = "aarch64" ] && OIDC_PAM_ARCH="arm64"

VERSION=$(curl -fsSL https://api.github.com/repos/scttfrdmn/oidc-pam/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "latest")

curl -fsSL "https://github.com/scttfrdmn/oidc-pam/releases/download/${VERSION}/oidc-pam_linux_${OIDC_PAM_ARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin/
chmod 755 /usr/local/bin/oidc-pam /usr/local/bin/oidc-auth-broker 2>/dev/null || true

# Install NSS/PAM modules
[ -f /usr/local/bin/pam_oidc.so ]    && cp /usr/local/bin/pam_oidc.so    /usr/lib64/security/pam_oidc.so
[ -f /usr/local/bin/libnss_oidc.so.2 ] && cp /usr/local/bin/libnss_oidc.so.2 /usr/lib64/libnss_oidc.so.2

# Configure broker
mkdir -p /etc/oidc-auth
cat > /etc/oidc-auth/broker.yaml <<BROKERCONF
issuer: "${OIDC_ISSUER}"
dynamodb_table: "${DYNAMODB_TABLE}"
aws_region: "${REGION}"
uid_range_min: 10000
uid_range_max: 60000
home_dir_prefix: /home
BROKERCONF
chmod 600 /etc/oidc-auth/broker.yaml

# NSS
if ! grep -q "oidc" /etc/nsswitch.conf; then
  sed -i 's/^passwd:\(.*\)/passwd:\1 oidc/' /etc/nsswitch.conf
  sed -i 's/^group:\(.*\)/group:\1 oidc/' /etc/nsswitch.conf
fi

# PAM
cat > /etc/pam.d/sshd-oidc <<'PAMCONF'
auth     required pam_oidc.so
account  required pam_oidc.so
session  optional pam_oidc.so
PAMCONF

# Start broker service
cat > /etc/systemd/system/oidc-auth-broker.service <<'SVCCONF'
[Unit]
Description=OIDC Auth Broker
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/oidc-auth-broker serve --config /etc/oidc-auth/broker.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCCONF

systemctl daemon-reload
systemctl enable --now oidc-auth-broker

echo "=== Head node setup complete ==="
