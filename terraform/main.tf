# ============================================================
# main.tf - Dựng lại đúng stack của docker-compose.yml bằng Terraform
# ============================================================
#
# BẢNG ĐỐI CHIẾU với docker-compose.yml:
#
#   compose                      ->  terraform
#   ---------------------------------------------------------
#   services.web                 ->  docker_container.web
#   services.db                  ->  docker_container.db
#   volumes.pgdata               ->  docker_volume.pgdata
#   mạng mặc định (tự tạo)       ->  docker_network.app  (phải khai báo TAY)
#   build: .                     ->  docker_image.web + build {}
#   depends_on                   ->  depends_on
#   healthcheck                  ->  healthcheck {}
#
# KHÁC BIỆT QUAN TRỌNG so với compose:
#   Compose tự tạo network cho bạn. Terraform thì KHÔNG tự làm gì cả -
#   cái gì muốn có là phải viết ra. Đổi lại, bạn kiểm soát được 100%
#   và nhìn file là biết chính xác hệ thống gồm những gì.

# ------------------------------------------------------------
# locals - giá trị tính toán nội bộ, không phải tham số đầu vào
# ------------------------------------------------------------
#
# Khác variable ở chỗ: variable là thứ NGƯỜI DÙNG truyền vào,
# local là thứ mình TỰ TÍNH ra để đỡ lặp code.

locals {
  # Ghép tiền tố tên 1 lần, dùng lại khắp nơi: "dictionary-dev"
  name_prefix = "${var.project_name}-${var.environment}"

  # Đường dẫn tới thư mục gốc project (thư mục cha của terraform/).
  # path.module = thư mục chứa file .tf đang đọc.
  project_root = abspath("${path.module}/..")

  # Nhãn gắn lên mọi tài nguyên - để sau này biết cái nào do Terraform tạo.
  # Rất hữu ích khi máy có hàng chục container lẫn lộn.
  common_labels = {
    "managed-by"  = "terraform"
    "project"     = var.project_name
    "environment" = var.environment
  }
}

# ------------------------------------------------------------
# NETWORK - mạng riêng để 2 container gọi nhau bằng TÊN
# ------------------------------------------------------------
#
# Đây là thứ compose làm ngầm mà Terraform bắt viết ra.
# Có mạng này thì container web gọi được "db" như một tên miền,
# không cần biết địa chỉ IP của nó là gì.

resource "docker_network" "app" {
  name = "${local.name_prefix}-net"

  # driver "bridge" = mạng ảo nội bộ trên 1 máy. Mặc định của Docker.
  driver = "bridge"

  # Vòng lặp tạo nhiều block label giống nhau từ map local.common_labels.
  # Cú pháp "dynamic" này là cách Terraform tránh phải copy-paste.
  dynamic "labels" {
    for_each = local.common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# ------------------------------------------------------------
# VOLUME - nơi chứa dữ liệu Postgres, sống sót qua việc xoá container
# ------------------------------------------------------------

resource "docker_volume" "pgdata" {
  name = "${local.name_prefix}-pgdata"

  # lifecycle điều khiển cách Terraform đối xử với tài nguyên này.
  # prevent_destroy = true -> terraform destroy sẽ BÁO LỖI và dừng lại,
  # không cho xoá. Đây là "chốt an toàn" cho dữ liệu quan trọng.
  #
  # Giá trị phải là hằng số lúc biên dịch nên không đặt var trực tiếp được,
  # ta đọc var qua điều kiện - đây là mẹo thường gặp.
  lifecycle {
    prevent_destroy = false # đổi thành true khi dùng cho môi trường thật
  }

  dynamic "labels" {
    for_each = local.common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# ------------------------------------------------------------
# BUILD IMAGE - vì sao dùng docker build chứ không dùng docker_image?
# ------------------------------------------------------------
#
# Cách "sách vở" là dùng resource docker_image kèm block build {}.
# NHƯNG: provider kreuzwerker/docker v3.9 nén build context bằng bộ build
# CŨ (legacy builder), còn Docker Engine 29 giải nén bằng pigz trong VM.
# Hai bên không khớp -> apply luôn lỗi:
#
#   Error running legacy build: failed to read dockerfile:
#   archive/tar: invalid tar header
#   unpigz: skipping: <stdin>: corrupted -- invalid deflate data
#
# Đã thử và KHÔNG khắc phục được bằng cấu hình: thêm .dockerignore,
# đổi build.version = "2", đổi sang thư mục không có dấu cách - vẫn lỗi.
# Đây là lỗi tương thích giữa provider và Engine 29, không phải lỗi code.
#
# Cách xử lý: để chính docker CLI (dùng BuildKit - luôn hoạt động) build image,
# Terraform chỉ điều phối. Đây là kỹ thuật "escape hatch" rất hay gặp trong
# thực tế: provider chưa hỗ trợ tốt thì gọi công cụ gốc, còn lại vẫn để
# Terraform quản lý. Đánh đổi: bước này Terraform không biết "diff" là gì,
# nó chỉ biết chạy lại lệnh khi chuỗi băm ở triggers_replace đổi.

# terraform_data là resource "trống" có sẵn trong Terraform (không cần provider).
# Dùng nó làm chỗ neo cho provisioner local-exec.
resource "terraform_data" "build_db_image" {
  # triggers_replace: đổi giá trị này -> Terraform huỷ và tạo lại resource
  # -> local-exec chạy lại -> image được build lại.
  # Y hệt vai trò của "triggers" trong docker_image.
  triggers_replace = {
    dockerfile_hash = filesha256("${local.project_root}/db/Dockerfile")
    initsql_hash    = filesha256("${local.project_root}/db/init.sql")
    image_tag       = "${local.name_prefix}-db:latest"
  }

  provisioner "local-exec" {
    # working_dir để lệnh docker build chạy đúng thư mục context
    working_dir = "${local.project_root}/db"
    command     = "docker build -t ${local.name_prefix}-db:latest ."
  }
}

resource "terraform_data" "build_web_image" {
  triggers_replace = {
    dockerfile_hash = filesha256("${local.project_root}/Dockerfile")
    server_hash     = filesha256("${local.project_root}/backend/server.js")
    db_js_hash      = filesha256("${local.project_root}/backend/db.js")
    app_jsx_hash    = filesha256("${local.project_root}/frontend/src/App.jsx")
    image_tag       = "${local.name_prefix}-web:latest"
  }

  provisioner "local-exec" {
    working_dir = local.project_root
    command     = "docker build -t ${local.name_prefix}-web:latest ."
  }
}

# ------------------------------------------------------------
# ĐỌC LẠI IMAGE vừa build - để lấy image_id thật (dạng sha256:...)
# ------------------------------------------------------------
#
# data source = CHỈ ĐỌC, không tạo gì. Khác resource là thứ Terraform TẠO RA.
# Ở đây ta hỏi Docker: "image tên này có id là gì?"
#
# depends_on bắt buộc phải có: nếu không, Terraform sẽ đọc image TRƯỚC khi
# lệnh build kịp chạy -> báo không tìm thấy image.

data "docker_image" "db" {
  name       = "${local.name_prefix}-db:latest"
  depends_on = [terraform_data.build_db_image]
}

data "docker_image" "web" {
  name       = "${local.name_prefix}-web:latest"
  depends_on = [terraform_data.build_web_image]
}

# ------------------------------------------------------------
# CONTAINER DB - PostgreSQL
# ------------------------------------------------------------

resource "docker_container" "db" {
  name = "${local.name_prefix}-db"

  # Tham chiếu tới resource khác bằng cú pháp <loại>.<tên>.<thuộc tính>.
  # Chính dòng này tạo ra QUAN HỆ PHỤ THUỘC: Terraform tự hiểu phải
  # build image xong mới tạo được container. Không cần khai báo thứ tự tay.
  image = data.docker_image.db.id

  # Biến môi trường - ở đây là list chuỗi "KEY=VALUE", khác cú pháp map của compose
  env = [
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_PASSWORD=${var.postgres_password}",
    "POSTGRES_DB=${var.postgres_db}",
  ]

  # Nối vào mạng riêng, đồng thời đặt "bí danh" là "db".
  # Nhờ alias này mà container web gọi host "db" là tới được đây -
  # đúng như DB_HOST=db trong docker-compose.yml.
  networks_advanced {
    name    = docker_network.app.name
    aliases = ["db"]
  }

  # Mở cổng ra host để cắm DBeaver/pgAdmin vào xem
  ports {
    internal = 5432
    external = var.db_port
  }

  # Gắn volume vào đúng thư mục dữ liệu của Postgres
  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  # Healthcheck: chờ Postgres THỰC SỰ nhận kết nối, không chỉ chờ
  # container khởi động. Giống hệt healthcheck trong compose.
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.postgres_user} -d ${var.postgres_db}"]
    interval = "5s"
    timeout  = "5s"
    retries  = 5
  }

  restart = "unless-stopped"

  # must_run = true -> Terraform coi container bị dừng là trạng thái SAI
  # và sẽ khởi động lại ở lần apply kế tiếp. Đây là "hội tụ trạng thái":
  # bạn mô tả trạng thái mong muốn, Terraform lo phần còn lại.
  must_run = true

  dynamic "labels" {
    for_each = local.common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}

# ------------------------------------------------------------
# CONTAINER WEB - React + Express
# ------------------------------------------------------------

resource "docker_container" "web" {
  name  = "${local.name_prefix}-web"
  image = data.docker_image.web.id

  env = [
    # DB_HOST trỏ tới alias "db" đã đặt ở networks_advanced bên trên
    "DB_HOST=db",
    "DB_PORT=5432",
    "DB_USER=${var.postgres_user}",
    "DB_PASSWORD=${var.postgres_password}",
    "DB_NAME=${var.postgres_db}",
  ]

  networks_advanced {
    name    = docker_network.app.name
    aliases = ["web"]
  }

  ports {
    internal = 3000
    external = var.web_port
  }

  restart  = "unless-stopped"
  must_run = true

  # depends_on: ép thứ tự tạo khi KHÔNG có tham chiếu trực tiếp.
  #
  # ĐIỂM KHÁC BIỆT LỚN so với compose, phải hiểu rõ:
  #   compose có "condition: service_healthy" -> chờ db khoẻ rồi mới chạy web.
  #   Terraform KHÔNG có cơ chế đó. depends_on chỉ đảm bảo db được TẠO trước,
  #   chứ không chờ Postgres sẵn sàng nhận kết nối.
  #
  # Thực tế không sao: backend/db.js dùng connection pool, lần query đầu
  # lỗi thì lần sau tự kết nối lại. Nhưng phải biết để không ngạc nhiên
  # khi thấy log web báo lỗi kết nối trong vài giây đầu.
  depends_on = [docker_container.db]

  dynamic "labels" {
    for_each = local.common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
}
