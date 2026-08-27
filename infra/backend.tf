terraform {
  # Partial backend: values come from -backend-config at init time.
  #
  #   terraform init -backend-config=config/backend.conf
  #
  # One state file for the whole project. Everything here is a single stack.
  backend "s3" {}
}
