# ============================================================
# main.tf - Hạ tầng AWS cho dictionary-app (chạy trên LocalStack)
# ============================================================
#
# Bài này dựng 4 nhóm tài nguyên AWS hay dùng nhất trong DevOps:
#
#   1. S3          - lưu file backup database
#   2. ECR         - "registry" riêng để chứa Docker image (thay GHCR)
#   3. IAM         - phân quyền: ai được làm gì
#   4. Secrets Mgr - cất mật khẩu đúng cách, không để trong file
#
# Toàn bộ cú pháp dưới đây là AWS THẬT. Đổi sang AWS thật chỉ cần sửa
# phần provider ở versions.tf.

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# data source = chỉ đọc thông tin, không tạo gì.
# aws_caller_identity trả về "tôi đang là ai" - account id, user id.
# Trên LocalStack luôn là account 000000000000.
data "aws_caller_identity" "current" {}

# ============================================================
# 1. S3 - Nơi lưu backup database
# ============================================================
#
# S3 (Simple Storage Service) là "ổ cứng trên mây": lưu file, trả phí
# theo dung lượng. Dùng cho backup, ảnh, file tĩnh, log...

resource "aws_s3_bucket" "backup" {
  # Tên bucket phải DUY NHẤT TRÊN TOÀN THẾ GIỚI (không chỉ trong account).
  # Nên thực tế luôn ghép thêm account id hoặc chuỗi ngẫu nhiên vào.
  bucket = "${local.name_prefix}-backup-${data.aws_caller_identity.current.account_id}"

  # force_destroy = true -> terraform destroy xoá được cả khi bucket còn file.
  # AWS mặc định KHÔNG cho xoá bucket còn dữ liệu (chốt an toàn).
  # Môi trường học thì bật lên cho dễ dọn, môi trường thật PHẢI để false.
  force_destroy = true
}

# Versioning: mỗi lần ghi đè file, S3 giữ lại bản cũ.
# Tác dụng thật: bị ransomware mã hoá file hoặc xoá nhầm thì phục hồi được.
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Mã hoá dữ liệu khi lưu (at rest). AWS thật bật sẵn từ 2023,
# nhưng viết ra rõ ràng là thói quen tốt - người đọc code biết ngay.
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Chặn mọi truy cập công khai. Đây là nguyên nhân hàng đầu gây rò rỉ
# dữ liệu trên AWS: bucket để public mà không biết.
# 4 dòng này nên có ở MỌI bucket trừ khi cố ý làm web tĩnh.
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----- Lifecycle rule: ĐÃ TẮT vì LocalStack Community không hỗ trợ -----
#
# Đoạn dưới là cú pháp ĐÚNG cho AWS thật (tự xoá file backup cũ để khỏi
# tốn tiền lưu trữ). Nhưng LocalStack Community không trả lời API này -
# Terraform sẽ treo 3 phút rồi báo:
#
#   timeout while waiting for state to become 'true'
#
# Đây là bài học quan trọng về LocalStack: nó giả lập PHẦN LỚN chứ không
# phải TẤT CẢ. Gặp lỗi kiểu này thì tra bảng hỗ trợ:
#   https://docs.localstack.cloud/references/coverage/
#
# Bỏ dấu # ở dưới khi deploy lên AWS thật.
#
# resource "aws_s3_bucket_lifecycle_configuration" "backup" {
#   bucket = aws_s3_bucket.backup.id
#
#   rule {
#     id     = "xoa-backup-cu"
#     status = "Enabled"
#     filter {}
#
#     # Xoá bản hiện tại sau N ngày
#     expiration {
#       days = var.backup_retention_days
#     }
#
#     # Xoá các bản cũ (do versioning sinh ra) sau 7 ngày
#     noncurrent_version_expiration {
#       noncurrent_days = 7
#     }
#   }
# }

# ============================================================
# 2. ECR - Registry riêng chứa Docker image
# ============================================================
#
# ECR (Elastic Container Registry) là Docker Hub riêng của bạn trên AWS.
# Buổi trước dùng GHCR của GitHub; trên AWS thì dùng ECR.

# !!! LOCALSTACK COMMUNITY KHÔNG HỖ TRỢ ECR - đây là tính năng bản Pro.
# Chạy thật sẽ nhận lỗi:
#
#   StatusCode: 501 ... api error InternalFailure:
#   API for service 'ecr' not yet implemented or pro feature
#
# Cú pháp bên dưới là ĐÚNG cho AWS thật, giữ lại để học và để dùng sau.
# Muốn thực hành registry miễn phí ngay bây giờ thì dùng GHCR của GitHub
# như buổi 6 đã làm - đó cũng là lựa chọn thực tế cho dự án nhỏ.

# resource "aws_ecr_repository" "web" {
#   name = "${local.name_prefix}-web"
#
#   # MUTABLE   : push lại tag :latest thì ghi đè - tiện nhưng nguy hiểm,
#   #             vì :latest hôm nay khác :latest hôm qua, không truy vết được.
#   # IMMUTABLE : tag đã push là KHÔNG sửa được - buộc mỗi build một tag riêng
#   #             (thường là git commit sha). Đây là chuẩn cho môi trường thật.
#   image_tag_mutability = "MUTABLE" # môi trường học để MUTABLE cho dễ thử
#
#   # Tự quét lỗ hổng bảo mật mỗi lần push image
#   image_scanning_configuration {
#     scan_on_push = true
#   }
#
#   force_delete = true # cho phép destroy khi repo còn image (chỉ dùng khi học)
# }
#
# # Lifecycle policy: ECR tính phí theo dung lượng, image cũ dồn lại rất tốn.
# # Rule này chỉ giữ 10 image mới nhất.
# #
# # Lưu ý cú pháp: policy của AWS viết bằng JSON. jsonencode() cho phép viết
# # bằng cú pháp HCL rồi Terraform tự chuyển thành JSON - đỡ sai dấu ngoặc
# # và vẫn dùng được biến.
# resource "aws_ecr_lifecycle_policy" "web" {
#   repository = aws_ecr_repository.web.name
#
#   policy = jsonencode({
#     rules = [
#       {
#         rulePriority = 1
#         description  = "Chi giu 10 image moi nhat"
#         selection = {
#           tagStatus   = "any"
#           countType   = "imageCountMoreThan"
#           countNumber = 10
#         }
#         action = {
#           type = "expire"
#         }
#       }
#     ]
#   })
# }

# ============================================================
# 3. SECRETS MANAGER - Cất mật khẩu đúng cách
# ============================================================
#
# Vì sao cần? Buổi 5 để mật khẩu trong .env, buổi 6 trong Jenkins credentials.
# Trên AWS, cách chuẩn là Secrets Manager: mật khẩu được mã hoá, phân quyền
# ai đọc được, có log mỗi lần truy cập, và tự đổi mật khẩu định kỳ được.
#
# Ứng dụng lúc chạy sẽ GỌI API để lấy mật khẩu, thay vì đọc từ biến môi trường.

resource "aws_secretsmanager_secret" "db" {
  name        = "${local.name_prefix}/database"
  description = "Thông tin kết nối database cho dictionary-app"

  # Số ngày chờ trước khi xoá thật (AWS thật mặc định 30 ngày để cứu khi xoá nhầm).
  # Đặt 0 = xoá ngay, chỉ dùng khi học để destroy cho nhanh.
  recovery_window_in_days = 0
}

# Giá trị của secret tách thành resource riêng - để sau này đổi mật khẩu
# mà không phải xoá/tạo lại cả cái secret.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  # Cất cả cụm thông tin dưới dạng JSON thay vì chỉ mật khẩu -
  # ứng dụng gọi 1 lần là có đủ thứ cần để kết nối.
  secret_string = jsonencode({
    username = "tuandev"
    password = var.db_password
    dbname   = "tudien"
    host     = "db"
    port     = 5432
  })
}

# ============================================================
# 4. IAM - Phân quyền
# ============================================================
#
# IAM (Identity and Access Management) trả lời câu hỏi: AI được làm GÌ
# với tài nguyên NÀO. Đây là phần khó nhất của AWS nhưng quan trọng nhất.
#
# Ba khái niệm phải phân biệt:
#   - Policy : tờ giấy ghi "được phép làm gì" (đọc S3, push ECR...)
#   - Role   : một "chức danh" mà máy/service khoác vào để có quyền
#   - User   : con người thật, đăng nhập bằng mật khẩu
#
# NGUYÊN TẮC VÀNG: least privilege - cấp đúng quyền tối thiểu cần thiết,
# không bao giờ cấp "*" (toàn quyền) cho tiện.

# ----- Policy: quyền ghi/đọc backup trong đúng 1 bucket -----
resource "aws_iam_policy" "backup_writer" {
  name        = "${local.name_prefix}-backup-writer"
  description = "Cho phép đọc/ghi file backup trong đúng bucket của project"

  policy = jsonencode({
    Version = "2012-10-17" # ngày này là phiên bản cú pháp, KHÔNG phải ngày tạo
    Statement = [
      {
        Sid    = "GhiDocFileTrongBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
        ]
        # Chỉ trong bucket này, không phải mọi bucket.
        # Dấu /* nghĩa là "mọi file BÊN TRONG bucket".
        Resource = "${aws_s3_bucket.backup.arn}/*"
      },
      {
        Sid    = "LietKeFileTrongBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        # Quyền liệt kê gắn vào CHÍNH bucket (không có /*) - đây là chỗ
        # rất nhiều người viết sai và không hiểu sao bị "Access Denied".
        Resource = aws_s3_bucket.backup.arn
      },
    ]
  })
}

# ----- Policy: quyền push image lên ECR (dùng cho CI/CD) -----
# Policy push ECR - tắt cùng với ECR ở trên (tham chiếu tới repo đã tắt).

# resource "aws_iam_policy" "ecr_push" {
#   name        = "${local.name_prefix}-ecr-push"
#   description = "Cho phép pipeline CI/CD đẩy image lên ECR"
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Sid    = "DangNhapECR"
#         Effect = "Allow"
#         # Riêng action lấy token đăng nhập buộc phải để Resource = "*"
#         # vì nó không gắn với repo nào cả. Đây là ngoại lệ hợp lý.
#         Action   = ["ecr:GetAuthorizationToken"]
#         Resource = "*"
#       },
#       {
#         Sid    = "PushPullImage"
#         Effect = "Allow"
#         Action = [
#           "ecr:BatchCheckLayerAvailability",
#           "ecr:InitiateLayerUpload",
#           "ecr:UploadLayerPart",
#           "ecr:CompleteLayerUpload",
#           "ecr:PutImage",
#           "ecr:BatchGetImage",
#           "ecr:GetDownloadUrlForLayer",
#         ]
#         # Chỉ đúng repo của project này
#         Resource = aws_ecr_repository.web.arn
#       },
#     ]
#   })
# }

# ----- Role: "chức danh" cho ứng dụng khoác vào -----
#
# assume_role_policy trả lời: AI được phép khoác chức danh này?
# Ở đây cho phép service EC2 - nghĩa là máy ảo EC2 chạy app sẽ tự động
# có quyền, KHÔNG cần nhét access key vào code. Đây là cách làm chuẩn:
# ứng dụng trên AWS không bao giờ nên chứa access key.
resource "aws_iam_role" "app" {
  name        = "${local.name_prefix}-app-role"
  description = "Role cho ứng dụng dictionary-app, có quyền ghi backup và đọc secret"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# ----- Policy đọc secret, viết kiểu inline (gắn trực tiếp vào role) -----
#
# Khác biệt:
#   aws_iam_policy          - policy độc lập, gắn được cho NHIỀU role
#   aws_iam_role_policy     - policy inline, sống/chết cùng 1 role duy nhất
# Dùng inline khi quyền đó chỉ dành riêng cho role này.
resource "aws_iam_role_policy" "read_secret" {
  name = "doc-secret-database"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db.arn
      }
    ]
  })
}

# ----- Gắn policy độc lập vào role -----
# Ba loại tài nguyên trên (policy, role, attachment) phải nối lại với nhau
# mới có tác dụng. Tạo policy mà không gắn vào đâu thì nó chỉ là tờ giấy.
resource "aws_iam_role_policy_attachment" "app_backup" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.backup_writer.arn
}

# ============================================================
# 5. Thử nghiệm: đẩy 1 file thật lên S3
# ============================================================
#
# Tạo hạ tầng xong thì phải chứng minh nó dùng được.
# Resource này upload file init.sql lên bucket vừa tạo.

resource "aws_s3_object" "schema_backup" {
  bucket = aws_s3_bucket.backup.id
  key    = "schema/init.sql" # "key" là đường dẫn file trong bucket

  # Đọc nội dung file từ máy. Dùng file() cho file text.
  source = "${abspath("${path.module}/..")}/db/init.sql"

  # etag là chuỗi băm MD5 - đổi nội dung file thì etag đổi -> Terraform
  # biết cần upload lại. Không có dòng này thì sửa file mà apply không làm gì.
  etag = filemd5("${abspath("${path.module}/..")}/db/init.sql")

  content_type = "application/sql"
}
