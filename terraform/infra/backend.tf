terraform {
  required_version = ">= 0.13"
  backend "s3" {
    bucket  = "tf-shopizer-20220401"
    key     = "infra.tfstate"
    region  = "eu-central-1"
  }
}

provider "aws" {
  region = var.aws_region
}
