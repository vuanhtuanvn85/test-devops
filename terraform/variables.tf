# ============================================================
# variables.tf - Tham số đầu vào (thay cho file .env của compose)
# ============================================================
#
# Mỗi "variable" là một tham số có thể đổi mà KHÔNG phải sửa code hạ tầng.
# Đây chính là vai trò của .env trong docker-compose, nhưng có thêm:
#   - type        : ép kiểu, sai kiểu là báo lỗi ngay lúc plan
#   - description : tự sinh tài liệu
#   - default     : giá trị mặc định, không truyền thì dùng cái này
#   - sensitive   : Terraform che giá trị này trong log và output
#   - validation  : tự kiểm tra giá trị hợp lệ trước khi tạo gì cả
#
# Thứ tự ưu tiên khi Terraform tìm giá trị (cao đè thấp):
#   1. -var="ten=gia_tri"        (dòng lệnh)
#   2. -var-file="file.tfvars"
#   3. terraform.tfvars          (tự động nạp)
#   4. biến môi trường TF_VAR_ten
#   5. default trong file này

# ---------- Kết nối tới Docker ----------

variable "docker_host" {
  description = "Đường dẫn socket của Docker daemon. Máy này dùng Docker Desktop nên socket nằm trong ~/.docker/run/, không phải /var/run/docker.sock như mặc định. Kiểm tra bằng: docker context inspect --format '{{.Endpoints.docker.Host}}'"
  type        = string
  default     = "unix:///Users/vuanhtuan/.docker/run/docker.sock"
}

# ---------- Đặt tên & môi trường ----------

variable "project_name" {
  description = "Tiền tố đặt tên cho mọi tài nguyên. Đổi cái này là dựng được stack thứ 2 song song mà không đụng tên."
  type        = string
  default     = "dictionary"
}

variable "environment" {
  description = "Tên môi trường, ghép vào tên tài nguyên: dictionary-dev-web, dictionary-staging-web..."
  type        = string
  default     = "dev"

  validation {
    # Chặn ngay từ lúc plan nếu gõ sai tên môi trường.
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment chỉ được là dev, staging hoặc prod."
  }
}

# ---------- Thông tin database ----------

variable "postgres_user" {
  description = "Tên user Postgres (tương ứng POSTGRES_USER trong .env)"
  type        = string
  default     = "tuandev"
}

variable "postgres_password" {
  description = "Mật khẩu Postgres (tương ứng POSTGRES_PASSWORD trong .env)"
  type        = string
  default     = "DongA@2026"

  # sensitive = true -> Terraform hiện (sensitive value) thay vì mật khẩu thật
  # trong output và plan. LƯU Ý: giá trị vẫn nằm DẠNG THƯỜNG trong file
  # terraform.tfstate. Đó là lý do .tfstate tuyệt đối không được commit.
  sensitive = true
}

variable "postgres_db" {
  description = "Tên database (tương ứng POSTGRES_DB trong .env)"
  type        = string
  default     = "tudien"
}

# ---------- Cổng mở ra máy host ----------

variable "web_port" {
  description = "Cổng trên máy host để vào web. KHÔNG dùng 8080 vì container Jenkins của buổi 6 đang giữ cổng đó; cũng tránh 3000 (stack dictionary-prod đang giữ). Đây chính là lý do cần tham số hoá cổng: mỗi stack một cổng, chạy song song không đụng nhau."
  type        = number
  default     = 8081

  validation {
    condition     = var.web_port > 1024 && var.web_port < 65536
    error_message = "web_port phải nằm trong khoảng 1025-65535 (dưới 1024 cần quyền root)."
  }
}

variable "db_port" {
  description = "Cổng trên máy host để nối DBeaver/pgAdmin vào Postgres. Tránh 5432 (stack dictionary-prod đang giữ)."
  type        = number
  default     = 55432
}

# ---------- Tuỳ chọn khác ----------

variable "postgres_image" {
  description = "Image gốc của Postgres. Ghim tag cụ thể, không dùng :latest - để lần apply sau không bất ngờ đổi phiên bản."
  type        = string
  default     = "postgres:16-alpine"
}

variable "keep_data_on_destroy" {
  description = "true  = terraform destroy vẫn GIỮ lại volume dữ liệu (giống docker compose down). false = xoá sạch luôn volume (giống docker compose down -v)."
  type        = bool
  default     = true
}
