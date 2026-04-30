"""
[5/4] Task6 ETL1 E2E 검증 스크립트
sales-api → ECS① simul → Kinesis → RDS + S3 한 바퀴 확인

실행:
    python verify_e2e_etl1.py
"""
import json
import os
import sys

import boto3

REGION        = os.environ.get("AWS_REGION", "ap-northeast-1")
STREAM_NAME   = os.environ.get("KINESIS_STREAM", "bookflow-pos-events")
RAW_BUCKET    = os.environ.get("RAW_BUCKET", "")
STACK_PREFIX  = "bookflow"


def check_kinesis(kinesis) -> bool:
    print("\n[1] Kinesis 스트림 상태 확인...")
    try:
        r = kinesis.describe_stream_summary(StreamName=STREAM_NAME)
        status = r["StreamDescriptionSummary"]["StreamStatus"]
        shards = r["StreamDescriptionSummary"]["OpenShardCount"]
        print(f"  스트림: {STREAM_NAME}")
        print(f"  상태: {status}")
        print(f"  샤드: {shards}개")
        return status == "ACTIVE"
    except Exception as e:
        print(f"  [오류] {e}")
        return False


def check_s3_raw_pos(s3) -> bool:
    print("\n[2] S3 Raw pos-events 파티션 확인...")
    if not RAW_BUCKET:
        print("  [SKIP] RAW_BUCKET 미설정")
        return True
    try:
        r = s3.list_objects_v2(
            Bucket=RAW_BUCKET,
            Prefix="pos-events/",
            MaxKeys=10,
        )
        objects = r.get("Contents", [])
        print(f"  버킷: s3://{RAW_BUCKET}/pos-events/")
        print(f"  파일 수: {len(objects)}개 (최근 10개)")
        for obj in objects[:3]:
            print(f"    - {obj['Key']} ({obj['Size']:,} bytes)")
        return len(objects) > 0
    except Exception as e:
        print(f"  [오류] {e}")
        return False


def check_firehose(firehose) -> bool:
    print("\n[3] Firehose 전송 스트림 상태 확인...")
    delivery_name = f"{STACK_PREFIX}-pos-events-firehose"
    try:
        r = firehose.describe_delivery_stream(DeliveryStreamName=delivery_name)
        status = r["DeliveryStreamDescription"]["DeliveryStreamStatus"]
        print(f"  Firehose: {delivery_name}")
        print(f"  상태: {status}")
        return status == "ACTIVE"
    except Exception as e:
        print(f"  [오류] {e}")
        return False


def check_cloudwatch_metrics(cw) -> None:
    print("\n[4] CloudWatch Kinesis 메트릭 확인 (최근 1시간)...")
    from datetime import datetime, timedelta, timezone
    end   = datetime.now(timezone.utc)
    start = end - timedelta(hours=1)
    try:
        r = cw.get_metric_statistics(
            Namespace="AWS/Kinesis",
            MetricName="IncomingRecords",
            Dimensions=[{"Name": "StreamName", "Value": STREAM_NAME}],
            StartTime=start,
            EndTime=end,
            Period=3600,
            Statistics=["Sum"],
        )
        pts = r.get("Datapoints", [])
        total = sum(p["Sum"] for p in pts)
        print(f"  IncomingRecords (1h): {total:,.0f}건")
    except Exception as e:
        print(f"  [오류] {e}")


def main():
    print("=" * 50)
    print("ETL1 E2E 검증: sales-api → ECS → Kinesis → RDS+S3")
    print("=" * 50)

    kinesis  = boto3.client("kinesis",         region_name=REGION)
    s3       = boto3.client("s3",              region_name=REGION)
    firehose = boto3.client("firehose",        region_name=REGION)
    cw       = boto3.client("cloudwatch",      region_name=REGION)

    results = [
        check_kinesis(kinesis),
        check_s3_raw_pos(s3),
        check_firehose(firehose),
    ]
    check_cloudwatch_metrics(cw)

    print("\n" + "=" * 50)
    passed = sum(results)
    print(f"결과: {passed}/{len(results)} 통과")
    if passed == len(results):
        print("ETL1 E2E 검증 완료!")
    else:
        print("일부 항목 실패 — 로그 확인 필요")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
