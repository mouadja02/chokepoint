locals {
  name_prefix = "${var.project_name}-${var.env}"

  ssm_prefix = "/${var.project_name}/${var.env}"
}
