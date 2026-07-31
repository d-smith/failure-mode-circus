terraform {
  backend "s3" {
    bucket         = "failure-mode-circus-tfstate-427848627088"
    key            = "scenarios/reference-service/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "failure-mode-circus-tflock"
    encrypt        = true
  }
}
