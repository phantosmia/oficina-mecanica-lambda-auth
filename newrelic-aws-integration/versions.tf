terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    newrelic = {
      source  = "newrelic/newrelic"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}
