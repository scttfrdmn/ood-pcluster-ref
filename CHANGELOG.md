# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial scaffold — reference AWS ParallelCluster configurations and OOD setup scripts for aws-openondemand.
- Cluster configs: `basic`, `burst`, `gpu`, and `hybrid` (`configs/*/cluster-config.yaml`).
- OOD cluster definition template (`ood-clusters/parallelcluster.yml.tmpl`).
- Setup scripts: `gen-cluster-yaml.sh`, `setup-head-node.sh`, and `setup-compute-nodes.sh`.
- CI workflow and Dependabot configuration.
