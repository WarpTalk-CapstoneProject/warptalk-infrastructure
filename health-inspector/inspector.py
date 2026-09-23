#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ServiceProbe:
    port: int
    path: str = "/health/ready"


@dataclass(frozen=True)
class CheckResult:
    name: str
    status: str
    detail: str
    category: str = "runtime"


EXPECTED_SERVICES: dict[str, ServiceProbe] = {
    "auth-service": ServiceProbe(5101),
    "workspace-service": ServiceProbe(5106),
    "translation-room-service": ServiceProbe(5102),
    "transcript-service": ServiceProbe(5103),
    "notification-service": ServiceProbe(5104),
    "meeting-service": ServiceProbe(5105),
    "assistant-service": ServiceProbe(5108),
    "billing-service": ServiceProbe(5107),
    "gateway": ServiceProbe(5200),
    "frontend": ServiceProbe(3000, "/"),
}

PRODUCTION_AI_SERVICES = {
    "stt-worker",
    "translation-worker",
    "tts-worker",
    "assistant-worker",
    "suggestion-worker",
    "embedding-worker",
    "billing-worker",
    "livekit-ingress-worker",
    "security-worker",
}

DATA_SERVICES = {"postgres", "pgbouncer", "minio", "minio-init", "qdrant"}

INFRA_SERVICES = {
    "redis",
    "rabbitmq",
    "otel-collector",
    "seq",
    "prometheus",
    "alertmanager",
    "grafana",
    "postgres-exporter",
    "billing-cost-exporter",
    "livekit-cost-exporter",
    "workspace-storage-exporter",
    "redis-exporter",
    "metrics-exporter",
}

LOCAL_AI_SERVICES = {
    "stt",
    "translation",
    "tts",
    "assistant",
    "embedding",
    "billing",
    "livekit-ingress",
    "security",
}

ONE_SHOT_SERVICES = {"migrator", "minio-init", "minio-workspace-provisioner"}

ERROR_PATTERN = re.compile(
    r"(?i)(\b(error|fatal|panic|critical)\b|unhandled(?:\s+exception)?|"
    r"[A-Za-z][A-Za-z0-9_.]+Exception\b|out\s+of\s+memory|oomkilled|segmentation\s+fault)"
)
IGNORE_PATTERNS = (
    re.compile(r"(?i)\b0\s+errors?\b"),
    re.compile(r"(?i)\berror\s+rate\s*[=:]\s*0(?:\.0+)?\b"),
    re.compile(r"(?i)\b(?:status|statuscode)\s*[=:]\s*200\b.*\berrors?\b"),
    re.compile(r"(?i)\b(?:GET|POST|PUT|PATCH|DELETE)\s+\S*errors?\S*.*\b(?:200|204|304)\b"),
    re.compile(r"(?i)\b(?:200|204|304)\b.*\b(?:GET|POST|PUT|PATCH|DELETE)\s+\S*errors?\S*"),
)
SECRET_PATTERNS = (
    (re.compile(r"(?i)(authorization\s*:\s*bearer\s+)[^\s,;]+"), r"\1[REDACTED]"),
    (re.compile(r"(?i)\b(password|secret|api[_-]?key|token)=([^\s,;]+)"), r"\1=[REDACTED]"),
)
TIMESTAMP_PREFIX = re.compile(
    r"^(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2}))\s+"
)
UUID_PATTERN = re.compile(r"\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b")
LONG_HEX_PATTERN = re.compile(r"\b[0-9a-fA-F]{16,}\b")
NUMBER_PATTERN = re.compile(r"\b\d+(?:\.\d+)?\b")


def redact(text: str) -> str:
    for pattern, replacement in SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def extract_log_findings(logs: str, limit: int) -> list[str]:
    findings: list[str] = []
    for raw_line in logs.splitlines():
        line = raw_line.strip()
        if not line or not ERROR_PATTERN.search(line):
            continue
        if any(pattern.search(line) for pattern in IGNORE_PATTERNS):
            continue
        findings.append(redact(line)[:1200])
        if len(findings) >= limit:
            break
    return findings


def group_log_findings(findings: list[str], limit: int) -> list[dict[str, Any]]:
    groups: dict[str, dict[str, Any]] = {}
    for line in findings:
        timestamp_match = TIMESTAMP_PREFIX.match(line)
        timestamp = timestamp_match.group("timestamp") if timestamp_match else None
        message = line[timestamp_match.end() :] if timestamp_match else line
        normalized = UUID_PATTERN.sub("<uuid>", message)
        normalized = LONG_HEX_PATTERN.sub("<hex>", normalized)
        normalized = NUMBER_PATTERN.sub("<n>", normalized)
        normalized = " ".join(normalized.lower().split())
        fingerprint = hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:12]
        group = groups.get(fingerprint)
        if group is None:
            groups[fingerprint] = {
                "fingerprint": fingerprint,
                "count": 1,
                "firstSeen": timestamp,
                "lastSeen": timestamp,
                "sample": line,
            }
            continue
        group["count"] += 1
        if timestamp:
            group["firstSeen"] = group["firstSeen"] or timestamp
            group["lastSeen"] = timestamp
    return sorted(groups.values(), key=lambda item: (-item["count"], item["fingerprint"]))[:limit]


def load_checkpoint(path: Path) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def save_checkpoint(path: Path, checkpoint: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(checkpoint, handle, indent=2, sort_keys=True)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def evaluate_container_state(
    service: str,
    state: dict[str, Any],
    restart_count: int,
    previous_restart_count: int | None = None,
) -> CheckResult:
    if state.get("OOMKilled"):
        return CheckResult(service, "critical", "container was OOM-killed")
    if state.get("Restarting"):
        return CheckResult(service, "critical", "container is restarting")
    if (
        service in ONE_SHOT_SERVICES
        and state.get("Status") == "exited"
        and state.get("ExitCode") == 0
    ):
        return CheckResult(service, "pass", "one-shot job completed successfully")
    if not state.get("Running"):
        status = state.get("Status", "missing")
        exit_code = state.get("ExitCode")
        return CheckResult(service, "critical", f"container is {status}, exit={exit_code}")

    health = state.get("Health", {}).get("Status")
    if health == "unhealthy":
        return CheckResult(service, "critical", "Docker health status is unhealthy")
    if health == "starting":
        return CheckResult(service, "warning", "Docker health status is still starting")
    if previous_restart_count is not None and restart_count > previous_restart_count:
        restart_delta = restart_count - previous_restart_count
        return CheckResult(
            service,
            "warning",
            f"running with {restart_delta} new restart(s) since previous inspection",
        )
    if health == "healthy":
        return CheckResult(service, "pass", "running; Docker health is healthy")
    return CheckResult(service, "pass", "running; application probe required")


def evaluate_port_publication(service: str, container: dict[str, Any]) -> CheckResult | None:
    """WT-595: a container that is Running and healthy while publishing nothing.

    This is the state that made the 30/08/2026 outage take 27 hours. After the VMs rebooted
    without their DHCP-assigned private address, `docker start` on the exited containers
    SUCCEEDED and they came up reporting healthy — the healthcheck (`pg_isready`, `redis-cli
    ping`) runs *inside* the container over loopback, so it knows nothing about whether the host
    published a port. `HostConfig.PortBindings` still held the full configuration; the live
    `NetworkSettings.Ports` was empty and the nat chain had no rule. Every cheap signal said the
    service was fine, and it was unreachable from every client.

    So the check is the disagreement itself: configured to publish, publishing nothing. Nothing
    else the inspector looks at can see this — which is why it is here rather than in a probe.

    Returns None when there is nothing to say: a container that publishes no ports by design
    (every .NET service on the App VM reaches its peers over the Compose network) must not be
    reported as broken for publishing none.
    """
    state = container.get("State", {})
    if not state.get("Running"):
        return None

    configured = container.get("HostConfig", {}).get("PortBindings") or {}
    if not configured:
        return None

    published = container.get("NetworkSettings", {}).get("Ports") or {}
    live = {port for port, bindings in published.items() if bindings}

    missing = sorted(port for port in configured if port not in live)
    if not missing:
        return None

    return CheckResult(
        service,
        "critical",
        "running and healthy but publishing nothing on "
        + ", ".join(missing)
        + " — the host has no listener for it. `docker start` cannot repair this; "
        "recreate with `docker compose up -d` (WT-595)",
    )


def result_exit_code(results: list[CheckResult]) -> int:
    if any(result.status == "critical" for result in results):
        return 2
    if any(result.status == "warning" for result in results):
        return 1
    return 0


def detect_role(services: set[str]) -> str:
    if "gateway" in services:
        return "app"
    if "postgres" in services and "qdrant" in services:
        return "data"
    if "redis" in services and "prometheus" in services:
        return "infra"
    return "app"


def required_services(role: str, present: set[str], require_ai: bool) -> set[str]:
    if role == "data":
        return set(DATA_SERVICES)
    if role == "infra":
        return set(INFRA_SERVICES)

    expected = set(EXPECTED_SERVICES)
    if require_ai or bool(present & PRODUCTION_AI_SERVICES):
        expected.update(PRODUCTION_AI_SERVICES)
    return expected


def docker(*args: str, allow_failure: bool = False) -> str:
    completed = subprocess.run(
        ["docker", *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode and not allow_failure:
        raise RuntimeError(redact(completed.stderr.strip() or "Docker command failed"))
    return completed.stdout


def docker_logs(container_id: str, since: str, tail: int, until: str | None = None) -> str:
    command = ["docker", "logs", "--timestamps", "--since", since]
    if until:
        command.extend(["--until", until])
    command.extend(["--tail", str(tail), container_id])
    completed = subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    # Docker preserves the original stdout/stderr streams. Both must be scanned:
    # many runtimes and console loggers intentionally send errors to stderr.
    return f"{completed.stdout}\n{completed.stderr}"


def ai_worker_probe(service: str, container_id: str) -> CheckResult:
    completed = subprocess.run(
        ["docker", "exec", container_id, "python", "-m", "shared.health_probe"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    detail = redact((completed.stderr or completed.stdout).strip())[:500]
    if completed.returncode == 0:
        return CheckResult(service, "pass", "in-container worker health probe passed", "probe")
    return CheckResult(
        service,
        "critical",
        f"in-container worker health probe failed: {detail or f'exit {completed.returncode}'}",
        "probe",
    )


def inspect_containers() -> list[dict[str, Any]]:
    ids = [line for line in docker("ps", "-aq").splitlines() if line]
    if not ids:
        return []
    return json.loads(docker("inspect", *ids))


def labels(container: dict[str, Any]) -> dict[str, str]:
    return container.get("Config", {}).get("Labels") or {}


def service_name(container: dict[str, Any]) -> str:
    return labels(container).get("com.docker.compose.service") or container["Name"].lstrip("/")


def project_name(container: dict[str, Any]) -> str:
    return labels(container).get("com.docker.compose.project", "")


def choose_project(containers: list[dict[str, Any]]) -> str:
    explicit = os.getenv("INSPECTOR_PROJECT", "").strip()
    if explicit:
        return explicit

    own_id = socket.gethostname()
    for container in containers:
        if container["Id"].startswith(own_id):
            own_project = project_name(container)
            if own_project:
                return own_project

    scores: dict[str, int] = {}
    for container in containers:
        project = project_name(container)
        if project and service_name(container) in EXPECTED_SERVICES:
            scores[project] = scores.get(project, 0) + 1
    if not scores:
        return ""
    return max(scores, key=lambda name: (scores[name], name == "warptalk-app"))


def http_probe(service: str, probe: ServiceProbe, timeout: float) -> CheckResult:
    url = f"http://{service}:{probe.port}{probe.path}"
    request = urllib.request.Request(url, headers={"User-Agent": "warptalk-health-inspector/1"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
        if 200 <= status < 400:
            return CheckResult(service, "pass", f"{probe.path} returned HTTP {status}", "probe")
        return CheckResult(service, "critical", f"{probe.path} returned HTTP {status}", "probe")
    except urllib.error.HTTPError as error:
        return CheckResult(service, "critical", f"{probe.path} returned HTTP {error.code}", "probe")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        reason = getattr(error, "reason", error)
        return CheckResult(service, "critical", f"{probe.path} failed: {redact(str(reason))}", "probe")


def run(args: argparse.Namespace) -> tuple[list[CheckResult], dict[str, list[dict[str, Any]]], str]:
    containers = inspect_containers()
    project = choose_project(containers)
    results: list[CheckResult] = []
    log_findings: dict[str, list[dict[str, Any]]] = {}
    checkpoint_path = Path(args.checkpoint) if args.checkpoint else None
    checkpoint = load_checkpoint(checkpoint_path) if checkpoint_path else {}
    previous_services = checkpoint.get("services", {})

    if not project:
        return [CheckResult("docker", "critical", "no WarpTalk Compose project found")], {}, ""

    selected = {
        service_name(container): container
        for container in containers
        if project_name(container) == project and service_name(container) != "health-inspector"
    }

    role = args.role if args.role != "auto" else detect_role(set(selected))
    expected = required_services(role, set(selected), args.require_ai)

    def previous_restarts(service: str, container: dict[str, Any]) -> int | None:
        previous = previous_services.get(service, {})
        if previous.get("containerId") != container.get("Id"):
            return None
        value = previous.get("restartCount")
        return value if isinstance(value, int) else None

    for service in sorted(expected):
        container = selected.get(service)
        if container is None:
            results.append(CheckResult(service, "critical", f"missing from Compose project {project}"))
            continue
        results.append(
            evaluate_container_state(
                service,
                container.get("State", {}),
                container.get("RestartCount", 0),
                previous_restarts(service, container),
            )
        )
        unpublished = evaluate_port_publication(service, container)
        if unpublished is not None:
            results.append(unpublished)

    for service, probe in EXPECTED_SERVICES.items():
        if role != "app":
            break
        container = selected.get(service)
        if container and container.get("State", {}).get("Running"):
            results.append(http_probe(service, probe, args.timeout))

    scope = []
    recognized_ai = PRODUCTION_AI_SERVICES | LOCAL_AI_SERVICES
    for container in containers:
        service = service_name(container)
        if service == "health-inspector":
            continue
        if project_name(container) == project or service in recognized_ai:
            scope.append(container)

    for container in scope:
        service = service_name(container)
        if service in recognized_ai and container.get("State", {}).get("Running"):
            results.append(ai_worker_probe(service, container["Id"]))

    already_checked = set(expected)
    for container in scope:
        service = service_name(container)
        if service not in already_checked:
            results.append(
                evaluate_container_state(
                    service,
                    container.get("State", {}),
                    container.get("RestartCount", 0),
                    previous_restarts(service, container),
                )
            )

        if args.no_logs:
            continue
        window_start = args.from_time or args.since
        raw_logs = docker_logs(container["Id"], window_start, args.log_tail, args.until)
        findings = extract_log_findings(raw_logs, max(args.log_tail * 2, args.max_log_findings))
        groups = group_log_findings(findings, args.max_log_findings)
        if groups:
            log_findings[service] = groups
            severity = "critical" if args.log_errors_critical else "warning"
            window = f"{window_start}..{args.until or 'now'}"
            results.append(
                CheckResult(
                    service,
                    severity,
                    f"{len(findings)} suspicious log line(s), "
                    f"{len(groups)} fingerprint(s) in {window}",
                    "logs",
                )
            )

    if checkpoint_path and not args.until:
        checkpoint_scope = {service_name(container): container for container in scope}
        checkpoint_scope.update(selected)
        save_checkpoint(
            checkpoint_path,
            {
                "checkedAt": datetime.now(timezone.utc).isoformat(),
                "services": {
                    service: {
                        "containerId": container.get("Id"),
                        "restartCount": container.get("RestartCount", 0),
                    }
                    for service, container in sorted(checkpoint_scope.items())
                },
            },
        )

    return results, log_findings, project



# ---------------------------------------------------------------------------------------------
# Kubernetes mode (--platform k8s). The same checks, answered from the API server instead of the
# Docker socket: workload availability, pod state (crash loops, OOM kills, restarts since the last
# inspection), node conditions, the data platform's own readiness, and the error fingerprints in
# each pod's recent logs. Read-only: it needs get/list on pods, pods/log, nodes and workloads
# (ClusterRole warptalk-inspector in deploy/k3s/cluster/deployer-rbac.yaml) and nothing else.
# ---------------------------------------------------------------------------------------------

K8S_NAMESPACES = {"app": "warptalk", "data": "warptalk-data", "monitoring": "monitoring", "traefik": "traefik"}
K8S_PLATFORM_DEPLOYMENTS = {"gotenberg", "warptalk-otel-collector", "seq"}
K8S_DATA_STATEFULSETS = {"warptalk-redis-node", "warptalk-qdrant"}
K8S_WAITING_CRITICAL = {
    "CrashLoopBackOff",
    "ImagePullBackOff",
    "ErrImagePull",
    "CreateContainerConfigError",
    "CreateContainerError",
    "InvalidImageName",
}


def kubectl(*args: str, allow_failure: bool = False) -> str:
    completed = subprocess.run(
        [os.getenv("KUBECTL", "kubectl"), *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode and not allow_failure:
        raise RuntimeError(redact(completed.stderr.strip() or "kubectl command failed"))
    return completed.stdout


def kubectl_items(*args: str) -> list[dict[str, Any]]:
    output = kubectl("get", *args, "-o", "json", allow_failure=True)
    if not output.strip():
        return []
    return json.loads(output).get("items", [])


def evaluate_deployment(deployment: dict[str, Any]) -> CheckResult:
    name = deployment["metadata"]["name"]
    desired = deployment.get("spec", {}).get("replicas", 1)
    status = deployment.get("status", {})
    available = status.get("availableReplicas", 0) or 0
    updated = status.get("updatedReplicas", 0) or 0
    if desired and available == 0:
        return CheckResult(name, "critical", f"0 of {desired} replica(s) available")
    if available < desired:
        return CheckResult(name, "warning", f"{available} of {desired} replica(s) available")
    if updated < desired:
        return CheckResult(name, "warning", f"rollout in progress: {updated} of {desired} updated")
    return CheckResult(name, "pass", f"{available}/{desired} replica(s) available")


def evaluate_statefulset(statefulset: dict[str, Any]) -> CheckResult:
    name = statefulset["metadata"]["name"]
    desired = statefulset.get("spec", {}).get("replicas", 1)
    ready = statefulset.get("status", {}).get("readyReplicas", 0) or 0
    if desired and ready == 0:
        return CheckResult(name, "critical", f"0 of {desired} replica(s) ready")
    if ready < desired:
        return CheckResult(name, "warning", f"{ready} of {desired} replica(s) ready")
    return CheckResult(name, "pass", f"{ready}/{desired} replica(s) ready")


def pod_service(pod: dict[str, Any]) -> str:
    labels_ = pod.get("metadata", {}).get("labels") or {}
    return (
        labels_.get("app.kubernetes.io/name")
        or labels_.get("cnpg.io/cluster")
        or labels_.get("app")
        or pod["metadata"]["name"]
    )


def evaluate_pod(
    pod: dict[str, Any], previous_restarts: dict[str, int] | None = None
) -> list[CheckResult]:
    """One result per container that is not healthy; nothing for a healthy pod."""
    name = f"{pod_service(pod)}/{pod['metadata']['name']}"
    status = pod.get("status", {})
    phase = status.get("phase", "Unknown")
    if phase == "Succeeded":
        return []
    if phase == "Failed":
        return [CheckResult(name, "critical", f"pod failed: {status.get('reason') or 'unknown reason'}")]
    if phase == "Pending":
        reason = next(
            (c.get("reason") for c in status.get("conditions", []) if c.get("status") == "False"),
            None,
        )
        return [CheckResult(name, "warning", f"pod is Pending ({reason or 'scheduling'})")]

    results: list[CheckResult] = []
    previous_restarts = previous_restarts or {}
    for container in status.get("containerStatuses", []) or []:
        container_name = f"{name}:{container.get('name')}"
        waiting = (container.get("state") or {}).get("waiting") or {}
        last = (container.get("lastState") or {}).get("terminated") or {}
        restarts = container.get("restartCount", 0) or 0
        previous = previous_restarts.get(container_name)
        if waiting.get("reason") in K8S_WAITING_CRITICAL:
            results.append(CheckResult(container_name, "critical", f"container is {waiting['reason']}"))
        elif previous is not None and restarts > previous:
            detail = f"{restarts - previous} new restart(s) since previous inspection"
            if last.get("reason") == "OOMKilled":
                results.append(CheckResult(container_name, "critical", f"{detail}; last exit OOMKilled"))
            else:
                reason = last.get("reason") or f"exit {last.get('exitCode')}"
                results.append(CheckResult(container_name, "warning", f"{detail}; last exit {reason}"))
        elif not container.get("ready"):
            results.append(CheckResult(container_name, "warning", "container is running but not ready"))
    return results


def evaluate_node(node: dict[str, Any]) -> CheckResult:
    name = f"node/{node['metadata']['name']}"
    conditions = {c.get("type"): c.get("status") for c in node.get("status", {}).get("conditions", [])}
    if conditions.get("Ready") != "True":
        return CheckResult(name, "critical", "node is not Ready")
    pressure = [kind for kind in ("MemoryPressure", "DiskPressure", "PIDPressure") if conditions.get(kind) == "True"]
    if pressure:
        return CheckResult(name, "warning", "node reports " + ", ".join(pressure))
    if node.get("spec", {}).get("unschedulable"):
        return CheckResult(name, "warning", "node is cordoned")
    return CheckResult(name, "pass", "Ready")


def within_until(line: str, until: str | None) -> bool:
    if not until:
        return True
    match = TIMESTAMP_PREFIX.match(line)
    if not match:
        return True
    return match.group("timestamp")[:19] <= until[:19]


def k8s_pod_logs(namespace: str, pod: str, args: argparse.Namespace) -> str:
    command = ["logs", pod, "--namespace", namespace, "--all-containers", "--timestamps", "--prefix"]
    if args.from_time:
        command.extend(["--since-time", args.from_time])
    else:
        command.extend(["--since", args.since])
    command.extend(["--tail", str(args.log_tail)])
    output = kubectl(*command, allow_failure=True)
    # --prefix writes "[pod/<name>/<container>] <timestamp> <message>"; drop it so fingerprints and
    # the timestamp parser see the same line shape as Docker logs.
    lines = [re.sub(r"^\[[^\]]+\]\s+", "", line) for line in output.splitlines()]
    return "\n".join(line for line in lines if within_until(line, args.until))


def run_k8s(args: argparse.Namespace) -> tuple[list[CheckResult], dict[str, list[dict[str, Any]]], str]:
    context = kubectl("config", "current-context", allow_failure=True).strip() or "unknown"
    roles = ("app", "data", "infra") if args.role in ("auto", "all") else (args.role,)
    results: list[CheckResult] = []
    log_findings: dict[str, list[dict[str, Any]]] = {}
    checkpoint_path = Path(args.checkpoint) if args.checkpoint else None
    checkpoint = load_checkpoint(checkpoint_path) if checkpoint_path else {}
    previous = checkpoint.get("k8sRestarts", {})
    current_restarts: dict[str, int] = {}
    scanned_namespaces: list[str] = []

    if "app" in roles:
        namespace = K8S_NAMESPACES["app"]
        scanned_namespaces.append(namespace)
        deployments = {d["metadata"]["name"]: d for d in kubectl_items("deployments", "--namespace", namespace)}
        expected = set(EXPECTED_SERVICES) | PRODUCTION_AI_SERVICES | K8S_PLATFORM_DEPLOYMENTS
        for name in sorted(expected):
            deployment = deployments.get(name)
            if deployment is None:
                results.append(CheckResult(name, "critical", f"Deployment missing from namespace {namespace}"))
            else:
                results.append(evaluate_deployment(deployment))
        for name in sorted(set(deployments) - expected):
            results.append(evaluate_deployment(deployments[name]))

    if "data" in roles:
        namespace = K8S_NAMESPACES["data"]
        scanned_namespaces.append(namespace)
        statefulsets = {s["metadata"]["name"]: s for s in kubectl_items("statefulsets", "--namespace", namespace)}
        for name in sorted(K8S_DATA_STATEFULSETS):
            if name not in statefulsets:
                results.append(CheckResult(name, "critical", f"StatefulSet missing from namespace {namespace}"))
            else:
                results.append(evaluate_statefulset(statefulsets[name]))
        for cluster in kubectl_items("clusters.postgresql.cnpg.io", "--namespace", namespace):
            name = f"postgres/{cluster['metadata']['name']}"
            desired = cluster.get("spec", {}).get("instances", 1)
            ready = cluster.get("status", {}).get("readyInstances", 0) or 0
            phase = cluster.get("status", {}).get("phase", "unknown")
            status = "pass" if ready == desired else ("critical" if ready == 0 else "warning")
            results.append(CheckResult(name, status, f"{ready}/{desired} instance(s) ready; {phase}"))
        rabbit = kubectl_items("rabbitmqclusters.rabbitmq.com", "--namespace", K8S_NAMESPACES["app"])
        for cluster in rabbit:
            ready = any(
                c.get("type") == "AllReplicasReady" and c.get("status") == "True"
                for c in cluster.get("status", {}).get("conditions", [])
            )
            results.append(
                CheckResult(
                    f"rabbitmq/{cluster['metadata']['name']}",
                    "pass" if ready else "critical",
                    "all replicas ready" if ready else "not all replicas ready",
                )
            )

    if "infra" in roles:
        for node in kubectl_items("nodes"):
            results.append(evaluate_node(node))
        for key in ("monitoring", "traefik"):
            namespace = K8S_NAMESPACES[key]
            scanned_namespaces.append(namespace)
            for deployment in kubectl_items("deployments", "--namespace", namespace):
                results.append(evaluate_deployment(deployment))

    for namespace in scanned_namespaces:
        for pod in kubectl_items("pods", "--namespace", namespace):
            restarts_before = {
                key.split("|", 1)[1]: value
                for key, value in previous.items()
                if key.startswith(pod["metadata"].get("uid", "") + "|")
            }
            results.extend(evaluate_pod(pod, restarts_before))
            for container in pod.get("status", {}).get("containerStatuses", []) or []:
                key = f"{pod['metadata'].get('uid', '')}|{pod_service(pod)}/{pod['metadata']['name']}:{container.get('name')}"
                current_restarts[key] = container.get("restartCount", 0) or 0
            if args.no_logs or pod.get("status", {}).get("phase") not in ("Running", "Failed"):
                continue
            service = pod_service(pod)
            raw_logs = k8s_pod_logs(namespace, pod["metadata"]["name"], args)
            findings = extract_log_findings(raw_logs, max(args.log_tail * 2, args.max_log_findings))
            groups = group_log_findings(findings, args.max_log_findings)
            if groups:
                existing = log_findings.setdefault(service, [])
                existing.extend(groups)
                severity = "critical" if args.log_errors_critical else "warning"
                window = f"{args.from_time or args.since}..{args.until or 'now'}"
                results.append(
                    CheckResult(
                        f"{service}/{pod['metadata']['name']}",
                        severity,
                        f"{len(findings)} suspicious log line(s), {len(groups)} fingerprint(s) in {window}",
                        "logs",
                    )
                )

    if checkpoint_path and not args.until:
        checkpoint["k8sRestarts"] = current_restarts
        checkpoint["checkedAt"] = datetime.now(timezone.utc).isoformat()
        save_checkpoint(checkpoint_path, checkpoint)

    return results, log_findings, f"k8s:{context}"


def render_human(
    results: list[CheckResult], log_findings: dict[str, list[dict[str, Any]]], project: str
) -> None:
    icons = {"pass": "PASS", "warning": "WARN", "critical": "FAIL"}
    print(f"WarpTalk health inspection | project={project or 'unknown'} | {datetime.now(timezone.utc).isoformat()}")
    print("=" * 88)
    for category in ("runtime", "probe", "logs"):
        category_results = [result for result in results if result.category == category]
        if not category_results:
            continue
        print(f"\n[{category.upper()}]")
        for result in category_results:
            print(f"{icons[result.status]:4} {result.name:32} {result.detail}")

    if log_findings:
        print("\n[LOG EVIDENCE - REDACTED]")
        for service, groups in sorted(log_findings.items()):
            for group in groups:
                seen = ""
                if group["firstSeen"]:
                    seen = f" first={group['firstSeen']} last={group['lastSeen']}"
                print(
                    f"{service}: [{group['fingerprint']}] count={group['count']}{seen} "
                    f"sample={group['sample']}"
                )

    counts = {status: sum(result.status == status for result in results) for status in icons}
    print(f"\nSUMMARY pass={counts['pass']} warning={counts['warning']} critical={counts['critical']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Inspect WarpTalk containers, readiness endpoints, and recent logs")
    parser.add_argument("--since", default=os.getenv("LOG_SINCE", "30m"), help="Docker log window, e.g. 30m or 2h")
    parser.add_argument("--from", dest="from_time", help="exact Docker log start time (RFC3339 or Docker format)")
    parser.add_argument("--until", help="exact Docker log end time (RFC3339 or Docker format)")
    parser.add_argument("--log-tail", type=int, default=3000, help="maximum log lines read per container")
    parser.add_argument("--max-log-findings", type=int, default=20, help="evidence lines retained per container")
    parser.add_argument("--timeout", type=float, default=5.0, help="HTTP probe timeout in seconds")
    parser.add_argument("--no-logs", action="store_true", help="skip recent Docker log inspection")
    parser.add_argument("--require-ai", action="store_true", help="require all production AI worker services")
    parser.add_argument(
        "--platform",
        choices=("docker", "k8s"),
        default=os.getenv("INSPECTOR_PLATFORM", "docker"),
        help="docker: the Compose host this runs on; k8s: the cluster KUBECONFIG points at",
    )
    parser.add_argument(
        "--role",
        choices=("auto", "all", "app", "data", "infra"),
        default="auto",
        help="host inventory to enforce; auto detects it from Compose services (k8s: all roles)",
    )
    parser.add_argument("--log-errors-critical", action="store_true", help="make suspicious log findings exit 2")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    parser.add_argument("--checkpoint", help="persist restart baselines to this JSON file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.platform == "k8s":
            results, log_findings, project = run_k8s(args)
        else:
            results, log_findings, project = run(args)
    except (RuntimeError, json.JSONDecodeError, FileNotFoundError) as error:
        results = [CheckResult("inspector", "critical", redact(str(error)))]
        log_findings = {}
        project = ""

    if args.json:
        print(
            json.dumps(
                {
                    "project": project,
                    "checkedAt": datetime.now(timezone.utc).isoformat(),
                    "exitCode": result_exit_code(results),
                    "results": [asdict(result) for result in results],
                    "logFindings": log_findings,
                },
                indent=2,
            )
        )
    else:
        render_human(results, log_findings, project)
    return result_exit_code(results)


if __name__ == "__main__":
    sys.exit(main())
