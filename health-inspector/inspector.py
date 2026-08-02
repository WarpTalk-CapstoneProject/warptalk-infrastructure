#!/usr/bin/env python3
from __future__ import annotations

import argparse
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


def evaluate_container_state(
    service: str, state: dict[str, Any], restart_count: int
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
    if restart_count > 0:
        return CheckResult(service, "warning", f"running with {restart_count} restart(s)")
    if health == "healthy":
        return CheckResult(service, "pass", "running; Docker health is healthy")
    return CheckResult(service, "pass", "running; application probe required")


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


def docker_logs(container_id: str, since: str, tail: int) -> str:
    completed = subprocess.run(
        ["docker", "logs", "--since", since, "--tail", str(tail), container_id],
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


def run(args: argparse.Namespace) -> tuple[list[CheckResult], dict[str, list[str]], str]:
    containers = inspect_containers()
    project = choose_project(containers)
    results: list[CheckResult] = []
    log_findings: dict[str, list[str]] = {}

    if not project:
        return [CheckResult("docker", "critical", "no WarpTalk Compose project found")], {}, ""

    selected = {
        service_name(container): container
        for container in containers
        if project_name(container) == project and service_name(container) != "health-inspector"
    }

    role = args.role if args.role != "auto" else detect_role(set(selected))
    expected = required_services(role, set(selected), args.require_ai)

    for service in sorted(expected):
        container = selected.get(service)
        if container is None:
            results.append(CheckResult(service, "critical", f"missing from Compose project {project}"))
            continue
        results.append(
            evaluate_container_state(service, container.get("State", {}), container.get("RestartCount", 0))
        )

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
                evaluate_container_state(service, container.get("State", {}), container.get("RestartCount", 0))
            )

        if args.no_logs:
            continue
        raw_logs = docker_logs(container["Id"], args.since, args.log_tail)
        findings = extract_log_findings(raw_logs, args.max_log_findings)
        if findings:
            log_findings[service] = findings
            severity = "critical" if args.log_errors_critical else "warning"
            results.append(
                CheckResult(service, severity, f"{len(findings)} suspicious log line(s) in {args.since}", "logs")
            )

    return results, log_findings, project


def render_human(results: list[CheckResult], log_findings: dict[str, list[str]], project: str) -> None:
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
        for service, findings in sorted(log_findings.items()):
            for line in findings:
                print(f"{service}: {line}")

    counts = {status: sum(result.status == status for result in results) for status in icons}
    print(f"\nSUMMARY pass={counts['pass']} warning={counts['warning']} critical={counts['critical']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Inspect WarpTalk containers, readiness endpoints, and recent logs")
    parser.add_argument("--since", default=os.getenv("LOG_SINCE", "30m"), help="Docker log window, e.g. 30m or 2h")
    parser.add_argument("--log-tail", type=int, default=3000, help="maximum log lines read per container")
    parser.add_argument("--max-log-findings", type=int, default=20, help="evidence lines retained per container")
    parser.add_argument("--timeout", type=float, default=5.0, help="HTTP probe timeout in seconds")
    parser.add_argument("--no-logs", action="store_true", help="skip recent Docker log inspection")
    parser.add_argument("--require-ai", action="store_true", help="require all production AI worker services")
    parser.add_argument(
        "--role",
        choices=("auto", "app", "data", "infra"),
        default="auto",
        help="host inventory to enforce; auto detects it from Compose services",
    )
    parser.add_argument("--log-errors-critical", action="store_true", help="make suspicious log findings exit 2")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        results, log_findings, project = run(args)
    except (RuntimeError, json.JSONDecodeError) as error:
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
