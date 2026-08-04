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
    group_log_findings,
    load_checkpoint,
    result_exit_code,
    required_services,
    save_checkpoint,
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

    def test_only_restarts_since_the_previous_checkpoint_are_visible(self):
        result = evaluate_container_state(
            "meeting-service",
            {"Status": "running", "Running": True, "OOMKilled": False, "Restarting": False},
            restart_count=4,
            previous_restart_count=3,
        )

        self.assertEqual("warning", result.status)
        self.assertIn("1 new restart", result.detail)

    def test_existing_restart_count_becomes_a_quiet_baseline(self):
        result = evaluate_container_state(
            "meeting-service",
            {"Status": "running", "Running": True, "OOMKilled": False, "Restarting": False},
            restart_count=3,
            previous_restart_count=3,
        )

        self.assertEqual("pass", result.status)
        self.assertNotIn("restart", result.detail)

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

    @patch("inspector.subprocess.run")
    def test_docker_logs_supports_an_exact_until_boundary(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = ""
        run.return_value.stderr = ""

        docker_logs(
            "container-id",
            "2026-08-01T04:30:00Z",
            100,
            until="2026-08-01T05:30:00Z",
        )

        command = run.call_args.args[0]
        self.assertIn("--timestamps", command)
        self.assertEqual("2026-08-01T05:30:00Z", command[command.index("--until") + 1])

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

    def test_groups_repeated_errors_with_dynamic_ids_into_one_fingerprint(self):
        findings = [
            "2026-08-01T04:31:00.000Z ERROR request 90b3896b-8869-43da-b417-cf4cd3d7c30e failed after 1200 ms",
            "2026-08-01T04:32:00.000Z ERROR request 2e6af4a4-c95d-4e66-b8b2-6de14e102aa1 failed after 1250 ms",
            "2026-08-01T04:33:00.000Z System.TimeoutException: upstream unavailable",
        ]

        groups = group_log_findings(findings, limit=10)

        self.assertEqual(2, len(groups))
        repeated = next(group for group in groups if group["count"] == 2)
        self.assertEqual("2026-08-01T04:31:00.000Z", repeated["firstSeen"])
        self.assertEqual("2026-08-01T04:32:00.000Z", repeated["lastSeen"])
        self.assertEqual(12, len(repeated["fingerprint"]))


class CheckpointTests(unittest.TestCase):
    def test_checkpoint_round_trip_is_persistent(self):
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "checkpoint.json"
            checkpoint = {
                "services": {"meeting-service": {"containerId": "abc", "restartCount": 3}}
            }

            save_checkpoint(path, checkpoint)

            self.assertEqual(checkpoint, load_checkpoint(path))

    def test_missing_checkpoint_starts_empty(self):
        self.assertEqual({}, load_checkpoint(Path("/path/that/does/not/exist.json")))


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
