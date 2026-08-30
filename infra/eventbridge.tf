# Once a day, after the upstream export refreshes -- it landed at 12:34 UTC on the day
# this was written. Re-running inside the same UTC hour overwrites its own keys, so a
# manual retry after a failure is safe.
module "snapshot_schedule" {
  source = "./modules/eventbridge-rule"

  rule_name           = "${local.name_prefix}-osv-snapshot"
  description         = "Daily OSV export snapshot into the staging bucket"
  schedule_expression = "cron(0 14 * * ? *)"

  targets = [{
    target_id = "snapshot"
    arn       = module.snapshot.function_arn
  }]
}

# The rule can't invoke the function without this, and the failure is silent: the rule
# fires, the target is skipped, and nothing shows up in the function's logs.
resource "aws_lambda_permission" "snapshot" {
  action        = "lambda:InvokeFunction"
  function_name = module.snapshot.function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.snapshot_schedule.rule_arn
}
