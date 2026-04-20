import json
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3


dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["ORDER_TABLE"])


def to_decimal(value):
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, list):
        return [to_decimal(v) for v in value]
    if isinstance(value, dict):
        return {k: to_decimal(v) for k, v in value.items()}
    return value


def response(body, status=200):
    return {
        "statusCode": status,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Content-Type": "application/json",
        },
        "body": json.dumps(body),
    }


def parse_body(event):
    raw_body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64
        raw_body = base64.b64decode(raw_body).decode("utf-8")
    return json.loads(raw_body)


def convert_decimal(obj):
    if isinstance(obj, list):
        return [convert_decimal(item) for item in obj]
    if isinstance(obj, dict):
        return {key: convert_decimal(value) for key, value in obj.items()}
    if isinstance(obj, Decimal):
        return float(obj)
    return obj


def lambda_handler(event, context):
    try:
        method = event.get("requestContext", {}).get("http", {}).get("method") or event.get("httpMethod")

        if method == "OPTIONS":
            return response({})

        if method == "POST":
            body = parse_body(event)

            cart_items = body.get("cart_items")
            total_amount = body.get("total_amount", 0)
            currency = body.get("currency", "INR")

            if not isinstance(cart_items, list) or len(cart_items) == 0:
                return response({"error": "cart_items must be a non-empty list"}, 400)

            order_id = str(uuid.uuid4())
            created_at = datetime.now(timezone.utc).isoformat()

            item = {
                "order_id": order_id,
                "created_at": created_at,
                "status": "PLACED",
                "currency": str(currency),
                "total_amount": Decimal(str(total_amount)),
                "cart_items": to_decimal(cart_items),
            }

            table.put_item(Item=item)

            return response(
                {
                    "message": "Order placed",
                    "order_id": order_id,
                    "status": "PLACED",
                    "created_at": created_at,
                },
                200,
            )

        if method == "GET":
            result = table.scan()
            items = convert_decimal(result.get("Items", []))
            items = sorted(items, key=lambda item: item.get("created_at", ""), reverse=True)
            return response(items, 200)

        return response({"error": "Method not allowed"}, 405)
    except Exception as error:
        return response({"error": str(error)}, 500)
