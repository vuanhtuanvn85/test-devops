# ============================================================
# versions.tf - Khai báo phiên bản Terraform và các provider
# ============================================================
#
# PROVIDER là gì? Là "plugin" giúp Terraform nói chuyện với một hệ thống
# cụ thể. Muốn tạo container thì cần provider Docker, muốn tạo máy ảo AWS
# thì cần provider AWS. Terraform lõi không biết gì về Docker hay AWS cả.
#
# Vì sao phải ghim phiên bản (~> 3.0)?
#   ~> 3.0  nghĩa là "cho phép 3.x bất kỳ, nhưng KHÔNG nhảy lên 4.0".
#   Provider phiên bản mới có thể đổi cú pháp -> code đang chạy ngon tự nhiên
#   hỏng. Ghim lại để hôm nay và 6 tháng sau chạy ra kết quả giống nhau.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      # Địa chỉ đầy đủ trên Terraform Registry: registry.terraform.io/kreuzwerker/docker
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Cấu hình provider: chỉ cho Terraform biết Docker daemon nằm ở đâu.
provider "docker" {
  host = var.docker_host
}
