# ============================================================
# variables.tf - Tham số cho phần AWS/LocalStack
# ============================================================

variable "localstack_endpoint" {
  description = "Địa chỉ LocalStack. Mọi service AWS đều đi qua cổng 4566 này."
  type        = string
  default     = "http://localhost:4566"
}

variable "aws_region" {
  description = "Region AWS. LocalStack không quan tâm region nào, nhưng cú pháp vẫn bắt buộc phải có - nên chọn luôn region gần Việt Nam để giống thật."
  type        = string
  default     = "ap-southeast-1" # Singapore
}

variable "project_name" {
  description = "Tên project, dùng làm tiền tố đặt tên tài nguyên"
  type        = string
  default     = "dictionary"
}

variable "environment" {
  description = "Tên môi trường"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment chỉ được là dev, staging hoặc prod."
  }
}

variable "db_password" {
  description = "Mật khẩu database - sẽ được cất vào AWS Secrets Manager thay vì để lộ trong file"
  type        = string
  default     = "DongA@2026"
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Số ngày giữ file backup trong S3 trước khi tự xoá (dùng cho lifecycle rule)"
  type        = number
  default     = 30
}
