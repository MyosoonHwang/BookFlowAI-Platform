"""
Scenario 11: GCP Cloud Function (bookflow-bq-load) failure scenario test

Problem:
  Glue Spark Job writes to GCS via .spark-staging-* / _temporary/ temp paths.
  GCS Eventarc triggers gcs-router Workflow -> bq-load tries to load already-deleted
  staging files -> 404 NotFound error.

Fix:
  Added .spark-staging- and /_temporary/ patterns to gcs_router Workflow
  filter_internal_artifacts condition (workflow.tf).

Test coverage:
  1. Filter pattern check   -- verify both patterns exist in live Workflow source
  2. Staging path ignored   -- invoke Workflow directly, expect ignored_internal_artifact
  3. Recent error check     -- inspect bq-load logs for 404 frequency
  4. Restore note           -- test is read-only; no state cleanup needed

Usage:
  python gcp_bq_load_cf_test.py test      # full auto test
  python gcp_bq_load_cf_test.py check     # filter pattern check only
  python gcp_bq_load_cf_test.py logs      # recent error logs only
"""
import json
import sys
import time
import subprocess

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PROJECT_ID = "project-8ab6bf05-54d2-4f5d-b8d"
REGION = "asia-northeast1"
BUCKET = "project-8ab6bf05-54d2-4f5d-b8d-bookflow-staging"
WORKFLOW_NAME = "bookflow-gcs-router"
FUNCTION_NAME = "bookflow-bq-load"

REQUIRED_FILTER_PATTERNS = [
    ".spark-staging-",
    "/_temporary/",
]

TEST_CASES = [
    {
        "name": "spark_staging path ignored",
        "object": "mart/features/.spark-staging-f6be252a/feature_date=2026-05-19/part-00001.parquet",
        "expected_route": "ignored_internal_artifact",
    },
    {
        "name": "_temporary path ignored",
        "object": "mart/features/_temporary/0/_temporary/attempt_123/part-00001.parquet",
        "expected_route": "ignored_internal_artifact",
    },
    {
        "name": "functions/ path ignored",
        "object": "functions/bookflow-bq-load.zip",
        "expected_route": "ignored_internal_artifact",
    },
    {
        "name": ".json path ignored",
        "object": "pipelines/bookflow-existing-books-pipeline.json",
        "expected_route": "ignored_internal_artifact",
    },
]


def _gcloud_exe() -> str:
    import shutil, sys
    # On Windows, gcloud is a .cmd batch file and needs shell=True or explicit .cmd path
    exe = shutil.which("gcloud.cmd") or shutil.which("gcloud")
    return exe or "gcloud"


def run_gcloud(args: list) -> tuple:
    """Run gcloud command. Uses shell=True on Windows for .cmd compatibility."""
    import shlex
    exe = _gcloud_exe()
    cmd = [exe] + args
    result = subprocess.run(
        cmd, capture_output=True, text=True, encoding="utf-8", shell=True,
    )
    return result.returncode, (result.stdout + result.stderr).strip()


def check_filter_patterns() -> bool:
    """Verify required filter patterns exist in live Workflow source."""
    print("\n[Filter Pattern Check]")
    code, output = run_gcloud([
        "workflows", "describe", WORKFLOW_NAME,
        "--location", REGION,
        "--format", "value(sourceContents)",
        "--project", PROJECT_ID,
    ])
    if code != 0:
        print(f"  [FAIL] Workflow describe failed: {output[:200]}")
        return False

    all_ok = True
    for pattern in REQUIRED_FILTER_PATTERNS:
        if pattern in output:
            print(f"  [OK] Pattern found: {pattern}")
        else:
            print(f"  [NG] Pattern missing: {pattern}")
            all_ok = False
    return all_ok


def run_workflow_test(test_case: dict) -> bool:
    """Execute Workflow via Python SDK and verify returned route."""
    from google.cloud import workflows_v1
    from google.cloud.workflows import executions_v1

    name = test_case["name"]
    obj = test_case["object"]
    expected = test_case["expected_route"]

    client = executions_v1.ExecutionsClient()
    workflow_path = (
        f"projects/{PROJECT_ID}/locations/{REGION}/workflows/{WORKFLOW_NAME}"
    )
    argument = json.dumps({"bucket": BUCKET, "name": obj})

    try:
        execution = client.create_execution(
            parent=workflow_path,
            execution=executions_v1.Execution(argument=argument),
        )
        # Poll until finished (max 60s)
        exec_name = execution.name
        for _ in range(30):
            time.sleep(2)
            execution = client.get_execution(name=exec_name)
            state = execution.state
            if state not in (
                executions_v1.Execution.State.ACTIVE,
                executions_v1.Execution.State.STATE_UNSPECIFIED,
            ):
                break

        if execution.result:
            route_data = json.loads(execution.result)
            route = route_data.get("route")
        else:
            route = None

        if route == expected:
            print(f"  [OK] {name} -> route={route}")
            return True
        else:
            error_msg = execution.error.payload if execution.error else ""
            print(f"  [NG] {name} -> expected={expected}, actual={route}")
            if error_msg:
                print(f"       error: {error_msg[:200]}")
            return False

    except Exception as e:
        print(f"  [NG] {name} -> exception: {e}")
        return False


def check_recent_errors() -> None:
    """Print 404/NotFound error count from recent bq-load logs."""
    print("\n[Recent bq-load Error Log Check]")
    code, output = run_gcloud([
        "functions", "logs", "read", FUNCTION_NAME,
        "--region", REGION,
        "--project", PROJECT_ID,
        "--limit", "100",
    ])
    if code != 0:
        print(f"  [FAIL] Log read failed: {output[:200]}")
        return

    lines = output.splitlines()
    not_found = [l for l in lines if "NotFound" in l or "404" in l]
    spark_errors = [l for l in not_found if ".spark-staging-" in l]

    print(f"  Total log lines : {len(lines)}")
    print(f"  404/NotFound    : {len(not_found)}")
    print(f"  spark-staging   : {len(spark_errors)}")

    if spark_errors:
        print("  [WARN] spark-staging errors still present")
        print("         (likely Eventarc retries from before fix -- will clear over time)")
    else:
        print("  [OK] No spark-staging 404 errors found")


def run_test() -> None:
    print("=" * 55)
    print("Scenario 11: bq-load Cloud Function Failure Test")
    print("=" * 55)

    # Step 1: filter pattern check
    filter_ok = check_filter_patterns()
    if not filter_ok:
        print("\n[ABORT] Filter patterns not applied.")
        print("        Run: cd infra/gcp/99-content-runtime && terraform apply")
        sys.exit(1)

    # Step 2: workflow routing tests (read-only, no GCS writes)
    print("\n[Workflow Routing Tests]")
    results = []
    for tc in TEST_CASES:
        ok = run_workflow_test(tc)
        results.append(ok)

    # Step 3: recent log check
    check_recent_errors()

    # Step 4: summary
    print("\n" + "=" * 55)
    passed = sum(results)
    total = len(results)
    if passed == total and filter_ok:
        print(f"PASS {passed}/{total} tests")
        print("  .spark-staging- and /_temporary/ paths are correctly filtered.")
    else:
        print(f"FAIL {passed}/{total} tests passed")

    print("\n[Restore Note]")
    print("  This test only invokes Workflows (read-only).")
    print("  No GCS objects created. No state changes. Nothing to restore.")
    print("  The workflow.tf filter change is a bug fix -- intentionally kept.")
    print("=" * 55)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""

    if cmd == "test":
        run_test()
    elif cmd == "check":
        check_filter_patterns()
    elif cmd == "logs":
        check_recent_errors()
    else:
        print(__doc__)
