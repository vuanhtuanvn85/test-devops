# ============================================================
# outputs.tf - Thông tin in ra sau khi apply
# ============================================================

output "s3_bucket_name" {
  description = "Tên bucket chứa backup"
  value       = aws_s3_bucket.backup.id
}

output "s3_bucket_arn" {
  description = "ARN của bucket. ARN (Amazon Resource Name) là 'số căn cước' duy nhất của mọi tài nguyên AWS, dạng arn:aws:s3:::ten-bucket - dùng khi viết policy."
  value       = aws_s3_bucket.backup.arn
}

# ECR bị tắt vì LocalStack Community không hỗ trợ (tính năng bản Pro).
# Mở lại khi chạy trên AWS thật:
#
# output "ecr_repository_url" {
#   description = "Địa chỉ ECR để docker push/pull"
#   value       = aws_ecr_repository.web.repository_url
# }

output "iam_role_arn" {
  description = "ARN của role cho ứng dụng"
  value       = aws_iam_role.app.arn
}

output "secret_arn" {
  description = "ARN của secret chứa thông tin database"
  value       = aws_secretsmanager_secret.db.arn
}

output "aws_account_id" {
  description = "Account ID đang dùng. LocalStack luôn trả 000000000000 - nhìn số này là biết đang chạy giả lập chứ không phải AWS thật."
  value       = data.aws_caller_identity.current.account_id
}

output "lenh_kiem_tra" {
  description = "Các lệnh aws-cli để kiểm chứng tài nguyên vừa tạo là thật"
  value       = <<-EOT

    Mọi lệnh đều thêm --endpoint-url để trỏ vào LocalStack thay vì AWS thật.
    Gõ tắt cho đỡ mỏi tay:  alias awsl='aws --endpoint-url=http://localhost:4566'

    Liệt kê bucket:       aws --endpoint-url=${var.localstack_endpoint} s3 ls
    Xem file trong bucket: aws --endpoint-url=${var.localstack_endpoint} s3 ls s3://${aws_s3_bucket.backup.id}/ --recursive
    Tải file về:          aws --endpoint-url=${var.localstack_endpoint} s3 cp s3://${aws_s3_bucket.backup.id}/schema/init.sql ./tai-ve.sql
    Đọc secret:           aws --endpoint-url=${var.localstack_endpoint} --region ${var.aws_region} secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.db.name} --query SecretString --output text
    Xem role:             aws --endpoint-url=${var.localstack_endpoint} --region ${var.aws_region} iam get-role --role-name ${aws_iam_role.app.name}
  EOT
}
