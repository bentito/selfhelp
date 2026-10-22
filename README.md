# selfhelp

The NIDS developer cluster scripts and documentation have moved to
[`openshift/network-edge-tools/dev-cluster`](https://github.com/openshift/network-edge-tools/tree/main/dev-cluster).
See the [setup and usage guide](https://github.com/openshift/network-edge-tools/blob/main/dev-cluster/README.md)
for cluster creation, container setup, AWS authentication, and teardown.

```bash
git clone git@github.com:openshift/network-edge-tools.git
cd network-edge-tools/dev-cluster
```

If you have an existing cluster, retain its `ocp-install-dir/` installer state
and place it in the new checkout's `dev-cluster/` directory before running
teardown there. Preserve `.ocp_cluster_counter` as well to continue the existing
cluster naming sequence.

The historical progress notes and containerization plan are preserved in the
new repository under `dev-cluster/docs/archive/`.
