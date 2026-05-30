# ood-pcluster-ref

[![CI](https://github.com/scttfrdmn/ood-pcluster-ref/actions/workflows/ci.yml/badge.svg)](https://github.com/scttfrdmn/ood-pcluster-ref/actions/workflows/ci.yml)
[![shellcheck](https://img.shields.io/badge/lint-shellcheck-89e051.svg)](https://www.shellcheck.net/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Reference AWS ParallelCluster configurations and OOD setup scripts for aws-openondemand.

## Contents

```
configs/
  basic/    CPU-only HPC cluster
  gpu/      CPU + GPU queue variant with FSx Lustre scratch
  burst/    Burst from on-prem SLURM to cloud compute nodes
  hybrid/   On-prem head node + cloud compute, oidc-pam on all nodes
scripts/
  setup-head-node.sh     Install oidc-pam NSS+PAM on head node
  setup-compute-nodes.sh Install oidc-pam NSS on compute nodes
  gen-cluster-yaml.sh    Generate OOD cluster YAML from a running cluster
ood-clusters/
  parallelcluster.yml.tmpl  OOD cluster YAML template
```

## Quick Start

1. Pick a config from `configs/` and copy it
2. Fill in your `SubnetId`, `FileSystemId`, and S3 bucket for scripts
3. Deploy the cluster:

```bash
pcluster create-cluster \
  --cluster-name my-hpc \
  --cluster-configuration configs/basic/cluster-config.yaml
```

4. Generate the OOD cluster config on your OOD portal node:

```bash
scp scripts/gen-cluster-yaml.sh ood-portal:/tmp/
ssh ood-portal sudo /tmp/gen-cluster-yaml.sh my-hpc --region us-east-1
```

## Identity Integration

All configs use `oidc-pam` for cloud-native identity:
- Head node runs `oidc-auth-broker` with PAM + NSS
- Compute nodes run `oidc-auth-broker` with NSS only
- UID mapping stored in DynamoDB (shared with OOD portal)

Users log in via OIDC (Cognito) on the OOD portal; the same UID follows them to the cluster.

## Related

- [aws-openondemand](https://github.com/scttfrdmn/aws-openondemand) — Terraform/CDK IaC
- [oidc-pam](https://github.com/scttfrdmn/oidc-pam) — OIDC→PAM bridge
