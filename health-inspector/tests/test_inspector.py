import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from inspector import (  # noqa: E402
    CheckResult,
    ai_worker_probe,
    docker_logs,
    detect_role,
    evaluate_container_state,
    extract_log_findings,
    result_exit_code,
    required_services,
)


class ContainerStateTests(unittest.TestCase):
    def test_running_container_without_docker_healthcheck_is_not_reported_healthy(self):
        result = evaluate_container_state(
            "auth-service",
            {"Status": "running", "Running": True, "OOMKilled": False, "Restarting": False},
            restart_count=0,
        )

        self.assertEqual("pass", result.status)
        self.assertIn("application probe required", result.detail)

    def test_unhealthy_container_is_critical(self):
        result = evaluate_container_state(
            "auth-service",
            {
                "Status": "running",
                "Running": True,
                "OOMKilled": False,
                "Restarting": False,
                "Health": {"Status": "unhealthy"},
            },
            restart_count=0,
        )

        self.assertEqual("critical", result.status)
        self.assertIn("unhealthy", result.detail)

    def test_recent_restarts_are_visible_even_when_container_is_running(self):
        result = evaluate_container_state(
            "meeting-service",
            {"Status": "running", "Running": True, "OOMKilled": False, "Restarting": False},
            restart_count=3,
        )

        self.assertEqual("warning", result.status)
        self.assertIn("3 restart", result.detail)

    def test_successful_migrator_exit_is_a_completed_job_not_an_outage(self):
        result = evaluate_container_state(
            "migrator",
            {
                "Status": "exited",
                "Running": False,
                "ExitCode": 0,
                "OOMKilled": False,
                "Restarting": False,
            },
            restart_count=0,
        )

        self.assertEqual("pass", result.status)
        self.assertIn("completed", result.detail)


class LogFindingTests(unittest.TestCase):
    @patch("inspector.subprocess.run")
    def test_docker_logs_combines_stdout_and_stderr(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = "normal output\n"
        run.return_value.stderr = "ERROR written to stderr\n"

        logs = docker_logs("container-id", "30m", 100)

        self.assertIn("normal output", logs)
        self.assertIn("ERROR written to stderr", logs)

    def test_detects_structured_and_plaintext_failures(self):
        logs = "\n".join(
            [
                json.dumps({"level": "Error", "message": "billing worker failed"}),
                "System.InvalidOperationException: sequence contains no elements",
                "panic: runtime failure",
            ]
        )

        findings = extract_log_findings(logs, limit=10)

        self.assertEqual(3, len(findings))
        self.assertTrue(any("billing worker failed" in line for line in findings))

    def test_ignores_common_success_lines_that_contain_error_words(self):
        logs = "\n".join(
            [
                "Health scan finished: 0 errors, 0 warnings",
                "HTTP request completed 200 /api/errors",
                "error rate = 0",
            ]
        )

        self.assertEqual([], extract_log_findings(logs, limit=10))

    def test_redacts_secrets_from_log_findings(self):
        logs = "ERROR Authorization: Bearer super-secret-token password=hunter2"

        findings = extract_log_findings(logs, limit=10)

        self.assertEqual(1, len(findings))
        self.assertNotIn("super-secret-token", findings[0])
        self.assertNotIn("hunter2", findings[0])


class ExitCodeTests(unittest.TestCase):
    def test_exit_codes_distinguish_healthy_warning_and_critical(self):
        self.assertEqual(0, result_exit_code([CheckResult("a", "pass", "ok")]))
        self.assertEqual(1, result_exit_code([CheckResult("a", "warning", "restart")]))
        self.assertEqual(2, result_exit_code([CheckResult("a", "critical", "down")]))


class AiWorkerProbeTests(unittest.TestCase):
    @patch("inspector.subprocess.run")
    def test_failed_in_container_health_probe_is_critical(self, run):
        run.return_value.returncode = 1
        run.return_value.stdout = ""
        run.return_value.stderr = "worker heartbeat is stale"

        result = ai_worker_probe("stt", "container-id")

        self.assertEqual("critical", result.status)
        self.assertIn("heartbeat is stale", result.detail)


class HostRoleTests(unittest.TestCase):
    def test_detects_each_production_host_role_from_service_inventory(self):
        self.assertEqual("app", detect_role({"gateway", "stt-worker"}))
        self.assertEqual("data", detect_role({"postgres", "qdrant"}))
        self.assertEqual("infra", detect_role({"redis", "prometheus"}))

    def test_data_role_does_not_require_application_microservices(self):
        expected = required_services("data", {"postgres", "pgbouncer", "minio", "qdrant"}, False)

        self.assertIn("postgres", expected)
        self.assertIn("qdrant", expected)
        self.assertNotIn("gateway", expected)

    def test_app_role_requires_all_ai_workers_when_any_production_worker_is_present(self):
        expected = required_services("app", {"gateway", "stt-worker"}, False)

        self.assertIn("gateway", expected)
        self.assertIn("security-worker", expected)


if __name__ == "__main__":
    unittest.main()
