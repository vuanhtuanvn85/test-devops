# ============================================================
# versions.tf - Provider AWS trỏ vào LocalStack thay vì AWS thật
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------
# ĐÂY LÀ PHẦN QUAN TRỌNG NHẤT CỦA BÀI NÀY
# ------------------------------------------------------------
#
# Cấu hình provider AWS bình thường chỉ cần region + credential.
# Để nó nói chuyện với LocalStack thay vì AWS thật, ta thêm 3 nhóm:
#
#   1. Credential giả     - LocalStack không kiểm tra, gõ gì cũng được
#   2. Tắt các bước kiểm tra - không gọi ra internet để xác thực
#   3. endpoints {}       - chuyển hướng MỌI service về localhost:4566
#
# ĐIỂM CẦN NHỚ: toàn bộ phần resource bên dưới (main.tf) là cú pháp AWS
# THẬT 100%. Muốn deploy lên AWS thật thì chỉ việc xoá 3 nhóm này đi,
# thay bằng credential thật - không sửa một dòng resource nào.
# Đó là lý do học bằng LocalStack vẫn ra kỹ năng dùng được.

provider "aws" {
  region = var.aws_region

  # ----- 1. Credential giả -----
  access_key = "test"
  secret_key = "test"

  # ----- 2. Tắt kiểm tra để không gọi ra AWS thật -----
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Với S3, LocalStack cần dạng địa chỉ "path-style":
  #   path-style    : http://localhost:4566/ten-bucket      <- LocalStack dùng cái này
  #   virtual-hosted: http://ten-bucket.s3.amazonaws.com    <- AWS thật dùng cái này
  s3_use_path_style = true

  # ----- 3. Chuyển hướng toàn bộ service về LocalStack -----
  # Mọi service AWS đều dùng chung 1 cổng 4566.
  endpoints {
    s3             = var.localstack_endpoint
    ecr            = var.localstack_endpoint
    iam            = var.localstack_endpoint
    sts            = var.localstack_endpoint
    secretsmanager = var.localstack_endpoint
    logs           = var.localstack_endpoint
  }

  # Tag tự động gắn vào MỌI tài nguyên tạo bởi provider này.
  # Thực tế cực kỳ hữu ích: lọc hoá đơn theo tag, biết tài nguyên nào của ai.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Course      = "DevOps-buoi7"
    }
  }
}
