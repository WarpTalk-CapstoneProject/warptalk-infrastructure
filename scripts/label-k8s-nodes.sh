#!/usr/bin/env bash
# Label and taint the cluster's nodes by role, idempotently. Run by the k8s release job (and the
# manual cluster bootstrap in deploy/k3s/README.md) before anything is deployed, so placement
# never depends on someone having typed the right `kubectl label` once.
#
#   K8S_APP_NODES    comma-separated node names -> node.warptalk.io/role=app
#   K8S_DATA_NODES   comma-separated node names -> node.warptalk.io/role=data
#                    + taint node.warptalk.io/role=data:NoSchedule (only data pods tolerate it)
#   K8S_INFRA_NODES  comma-separated node names -> node.warptalk.io/role=infra
#                    (the control plane keeps kubeadm's own control-plane taint)
#   K8S_DRY_RUN=true validates every patch server-side without applying it.
#
# With the three lists empty, roles are resolved from addresses the workflow already knows, so no
# node name has to be configured anywhere:
#   K8S_DATA_NODE_IP   node whose InternalIP is this (vars.PRODUCTION_DATA_HOST) -> data
#   K8S_INFRA_NODE_IP  node whose InternalIP is this (vars.PRODUCTION_INFRA_HOST), or the node
#                      carrying node-role.kubernetes.io/control-plane           -> infra
#   every other node                                                              -> app
set -euo pipefail

[ -n "${KUBECONFIG:-}" ] || { echo "label-k8s-nodes: KUBECONFIG must name the target cluster explicitly" >&2; exit 1; }
export KUBECONFIG
K8S_APP_NODES="${K8S_APP_NODES:-}"
K8S_DATA_NODES="${K8S_DATA_NODES:-}"
K8S_INFRA_NODES="${K8S_INFRA_NODES:-}"
K8S_DATA_NODE_IP="${K8S_DATA_NODE_IP:-}"
K8S_INFRA_NODE_IP="${K8S_INFRA_NODE_IP:-}"
K8S_DRY_RUN="${K8S_DRY_RUN:-false}"

role_label="node.warptalk.io/role"

fail() {
  echo "label-k8s-nodes: $*" >&2
  exit 1
}

dry_run_args=()
if [ "$K8S_DRY_RUN" = "true" ]; then
  dry_run_args=(--dry-run=server)
fi

valid_node_name() {
  case "$1" in
    ""|*[!a-z0-9.-]*) return 1 ;;
  esac
}

apply_role() {
  local role="$1" nodes="$2" node
  local IFS=','
  for node in $nodes; do
    valid_node_name "$node" || fail "unsafe node name: '$node'"
    kubectl get node "$node" >/dev/null || fail "node $node does not exist"
    kubectl label node "$node" "$role_label=$role" --overwrite ${dry_run_args[@]+"${dry_run_args[@]}"}
    if [ "$role" = "data" ]; then
      kubectl taint node "$node" "$role_label=data:NoSchedule" --overwrite ${dry_run_args[@]+"${dry_run_args[@]}"}
    elif kubectl get node "$node" -o json |
      jq -e --arg key "$role_label" 'any(.spec.taints[]?; .key == $key)' >/dev/null; then
      # A node that used to be a data node must not keep repelling application pods.
      kubectl taint node "$node" "$role_label-" ${dry_run_args[@]+"${dry_run_args[@]}"}
    fi
  done
}

nodes_json="$(kubectl get nodes -o json)"
if [ -z "$K8S_APP_NODES$K8S_DATA_NODES$K8S_INFRA_NODES" ] &&
  printf '%s\n' "$nodes_json" | jq -e --arg key "$role_label" '
    [.items[].metadata.labels[$key] // empty] | (index("app") and index("data") and index("infra"))' >/dev/null; then
  # The cluster already carries one of each role: those labels are the record. Re-apply them
  # (and the Data taint) rather than re-deriving roles from addresses.
  resolved="$(printf '%s\n' "$nodes_json" | jq -r --arg key "$role_label" '
    [.items[] | {name: .metadata.name, role: .metadata.labels[$key]}] as $nodes
    | ["app", "data", "infra"]
    | map(. as $r | [$nodes[] | select(.role == $r) | .name] | join(","))
    | join("|")')"
  IFS='|' read -r K8S_APP_NODES K8S_DATA_NODES K8S_INFRA_NODES <<<"$resolved"
elif [ -z "$K8S_APP_NODES$K8S_DATA_NODES$K8S_INFRA_NODES" ]; then
  [ -n "$K8S_DATA_NODE_IP" ] || fail "set K8S_*_NODES, or K8S_DATA_NODE_IP to resolve them"
  resolved="$(printf '%s\n' "$nodes_json" | jq -r \
    --arg data "$K8S_DATA_NODE_IP" --arg infra "$K8S_INFRA_NODE_IP" '
    def ip: [.status.addresses[]? | .address];
    def role:
      if (ip | index($data)) then "data"
      elif ($infra != "" and (ip | index($infra))) then "infra"
      elif (.metadata.labels["node-role.kubernetes.io/control-plane"] != null) then "infra"
      else "app" end;
    [.items[] | {name: .metadata.name, role: role}] as $nodes
    | ["app", "data", "infra"]
    | map(. as $r | [$nodes[] | select(.role == $r) | .name] | join(","))
    | join("|")')"
  # "|" rather than a tab: IFS whitespace would collapse an empty role and shift the others.
  IFS='|' read -r K8S_APP_NODES K8S_DATA_NODES K8S_INFRA_NODES <<<"$resolved"
fi
[ -n "$K8S_APP_NODES" ] || fail "no App node resolved"
[ -n "$K8S_DATA_NODES" ] || fail "no Data node resolved (is K8S_DATA_NODE_IP a node InternalIP?)"
[ -n "$K8S_INFRA_NODES" ] || fail "no Infra node resolved"

apply_role app "$K8S_APP_NODES"
apply_role data "$K8S_DATA_NODES"
apply_role infra "$K8S_INFRA_NODES"

# Every Ready node must have exactly one role; an unlabelled node would receive no WarpTalk pods
# and quietly shrink capacity.
unlabelled="$(kubectl get nodes -o json | jq -r --arg key "$role_label" '
  [.items[] | select(.metadata.labels[$key] == null) | .metadata.name] | join(",")')"
if [ -n "$unlabelled" ] && [ "$K8S_DRY_RUN" != "true" ]; then
  fail "nodes without a $role_label label: $unlabelled"
fi
echo "Node roles applied (app=$K8S_APP_NODES data=$K8S_DATA_NODES infra=$K8S_INFRA_NODES)"
