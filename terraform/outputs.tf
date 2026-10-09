# ============================================================
# outputs.tf - Giá trị Terraform in ra sau khi apply xong
# ============================================================
#
# Output dùng để làm gì?
#   1. Cho NGƯỜI đọc: apply xong hiện luôn link để bấm vào, không phải đi tra
#   2. Cho MÁY đọc: terraform output -json | jq  -> nối vào script CI/CD
#   3. Cho MODULE khác đọc: module A xuất ra, module B dùng làm input
#
# Xem lại bất cứ lúc nào:  terraform output
# Xem 1 giá trị cụ thể:    terraform output -raw web_url

output "web_url" {
  description = "Mở link này trên trình duyệt để dùng app"
  value       = "http://localhost:${var.web_port}"
}

output "health_check_url" {
  description = "API kiểm tra kết nối database - dùng để smoke test"
  value       = "http://localhost:${var.web_port}/api/health"
}

output "database_connection" {
  description = "Thông tin cắm vào DBeaver/pgAdmin (mật khẩu xem bằng: terraform output -raw db_password)"
  value = {
    host     = "localhost"
    port     = var.db_port
    database = var.postgres_db
    username = var.postgres_user
  }
}

output "db_password" {
  description = "Mật khẩu database. Có sensitive = true nên 'terraform output' che lại, muốn xem thật phải gõ: terraform output -raw db_password"
  value       = var.postgres_password
  sensitive   = true
}

output "container_names" {
  description = "Tên 2 container vừa tạo - dùng cho docker logs / docker exec"
  value = {
    web = docker_container.web.name
    db  = docker_container.db.name
  }
}

output "network_name" {
  description = "Tên mạng riêng của stack"
  value       = docker_network.app.name
}

output "huong_dan_nhanh" {
  description = "Các lệnh hay dùng nhất, in sẵn ra cho tiện copy"
  value       = <<-EOT

    Xem log web:      docker logs -f ${docker_container.web.name}
    Xem log db:       docker logs -f ${docker_container.db.name}
    Vào psql:         docker exec -it ${docker_container.db.name} psql -U ${var.postgres_user} -d ${var.postgres_db}
    Thử API health:   curl -s http://localhost:${var.web_port}/api/health
    Tra 1 từ:         curl -s http://localhost:${var.web_port}/api/define/computer
    Dẹp toàn bộ:      terraform destroy
  EOT
}
