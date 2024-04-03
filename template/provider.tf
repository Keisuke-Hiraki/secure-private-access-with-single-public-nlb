# プロバイダー設定
provider "aws" {
  region = "ap-northeast-1" # 適切なリージョンを指定してください
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.15.0"
    }
  }
}