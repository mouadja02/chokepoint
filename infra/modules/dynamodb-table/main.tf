resource "aws_dynamodb_table" "this" {
  name                        = var.table_name
  billing_mode                = var.billing_mode
  hash_key                    = var.hash_key
  range_key                   = var.range_key
  deletion_protection_enabled = var.deletion_protection
  stream_enabled              = var.stream_view_type != null
  stream_view_type            = var.stream_view_type

  dynamic "attribute" {
    for_each = var.attributes

    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes

    content {
      name               = global_secondary_index.value.name
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes

      # hash_key/range_key on a GSI are deprecated in favour of key_schema. One
      # dynamic block rather than a static HASH plus a dynamic RANGE, so the order
      # doesn't depend on how HCL merges static and dynamic blocks of the same name.
      dynamic "key_schema" {
        for_each = concat(
          [{ attribute_name = global_secondary_index.value.hash_key, key_type = "HASH" }],
          global_secondary_index.value.range_key == null ? [] : [
            { attribute_name = global_secondary_index.value.range_key, key_type = "RANGE" }
          ],
        )

        content {
          attribute_name = key_schema.value.attribute_name
          key_type       = key_schema.value.key_type
        }
      }
    }
  }

  dynamic "ttl" {
    for_each = var.ttl_attribute != null ? [1] : []

    content {
      attribute_name = var.ttl_attribute
      enabled        = true
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  dynamic "server_side_encryption" {
    for_each = var.kms_key_arn != null ? [1] : []

    content {
      enabled     = true
      kms_key_arn = var.kms_key_arn
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "read_throttles" {
  alarm_name          = "${var.table_name}-read-throttles"
  alarm_description   = "DynamoDB table ${var.table_name} has throttled reads"
  namespace           = "AWS/DynamoDB"
  metric_name         = "ReadThrottleEvents"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.this.name
  }
}

resource "aws_cloudwatch_metric_alarm" "write_throttles" {
  alarm_name          = "${var.table_name}-write-throttles"
  alarm_description   = "DynamoDB table ${var.table_name} has throttled writes"
  namespace           = "AWS/DynamoDB"
  metric_name         = "WriteThrottleEvents"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.this.name
  }
}
