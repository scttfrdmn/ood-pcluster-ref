#!/usr/bin/env bash
# Install oidc-pam NSS module on ParallelCluster compute nodes.
# Compute nodes only need NSS (for UID resolution); PAM auth is on head node.
#
# Args:
#   --dynamodb-table=NAME   DynamoDB UID mapping table name
set -euo pipefail

DYNAMODB_TABLE=""
for arg in "$@"; do
  case "${arg}" in
    --dynamodb-table=*) DYNAMODB_TABLE="${arg#*=}" ;;
  esac
done

REGION=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" | \
  xargs -I{} curl -s -H "X-aws-ec2-metadata-token: {}" \
  "http://169.254.169.254/latest/meta-data/placement/region")

echo "=== Setting up oidc-pam NSS on compute node ==="

ARCH=$(uname -m)
OIDC_PAM_ARCH="amd64"
[ "${ARCH}" = "aarch64" ] && OIDC_PAM_ARCH="arm64"

VERSION=$(curl -fsSL https://api.github.com/repos/scttfrdmn/oidc-pam/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "latest")

curl -fsSL "https://github.com/scttfrdmn/oidc-pam/releases/download/${VERSION}/oidc-pam_linux_${OIDC_PAM_ARCH}.tar.gz" \
  | tar -xz -C /usr/local/bin/
chmod 755 /usr/local/bin/oidc-auth-broker 2>/dev/null || true

[ -f /usr/local/bin/libnss_oidc.so.2 ] && cp /usr/local/bin/libnss_oidc.so.2 /usr/lib64/libnss_oidc.so.2

# Minimal broker config (read-only UID lookups, no PAM auth)
mkdir -p /etc/oidc-auth
cat > /etc/oidc-auth/broker.yaml <<BROKERCONF
dynamodb_table: "${DYNAMODB_TABLE}"
aws_region: "${REGION}"
uid_range_min: 10000
uid_range_max: 60000
home_dir_prefix: /home
BROKERCONF
chmod 600 /etc/oidc-auth/broker.yaml

if ! grep -q "oidc" /etc/nsswitch.conf; then
  sed -i 's/^passwd:\(.*\)/passwd:\1 oidc/' /etc/nsswitch.conf
  sed -i 's/^group:\(.*\)/group:\1 oidc/' /etc/nsswitch.conf
fi

cat > /etc/systemd/system/oidc-auth-broker.service <<'SVCCONF'
[Unit]
Description=OIDC Auth Broker (NSS only)
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

echo "=== Compute node setup complete ==="
