# BUỔI 7 — Terraform: Hạ tầng viết bằng code

> Mục tiêu: dựng lại đúng stack dictionary-app bằng Terraform thay cho
> `docker compose up`, rồi tập cú pháp AWS trên LocalStack — tất cả **miễn phí,
> không cần thẻ tín dụng**.

---

## 1. Terraform giải quyết vấn đề gì mà Compose không làm được?

Compose đã dựng được cả stack rồi, vậy cần Terraform làm gì?

Khác biệt nằm ở **phạm vi**:

| | Docker Compose | Terraform |
| --- | --- | --- |
| Quản lý được | Chỉ container trên 1 máy | Container, máy ảo, mạng, DNS, database, S3, Kubernetes… |
| Nhà cung cấp | Chỉ Docker | ~4000 provider: AWS, Azure, GCP, Cloudflare, GitHub… |
| Biết trước thay đổi | Không | **Có** — `terraform plan` |
| Nhớ đã tạo gì | Không | **Có** — file state |
| Xoá sạch | `down` (chỉ thứ nó tạo) | `destroy` (mọi thứ trong state) |

Ba thứ Terraform có mà Compose không có, đáng tiền nhất:

**a) `terraform plan` — xem trước khi làm.** Compose chạy là chạy luôn.
Terraform cho bạn đọc bản kê "sẽ tạo 6 thứ, sửa 1 thứ, xoá 0 thứ" trước khi
bấm nút. Trong môi trường thật, đây là thứ cứu bạn khỏi xoá nhầm database.

**b) State — sổ ghi chép.** Terraform nhớ nó đã tạo gì. Nhờ vậy nó biết
so sánh "thực tế" với "mong muốn" và chỉ sửa đúng phần lệch.

**c) Một ngôn ngữ cho mọi tầng.** Cùng cú pháp HCL để tạo container hôm nay
và tạo cả cụm Kubernetes trên AWS ngày mai.

---

## 2. Vòng đời Terraform — 4 lệnh phải thuộc

```
   terraform init      →  Tải provider về (chạy 1 lần, hoặc khi đổi provider)
          ↓
   terraform plan      →  So sánh MONG MUỐN (file .tf) với THỰC TẾ (state)
          ↓              In ra: sẽ thêm gì / sửa gì / xoá gì. KHÔNG đụng gì cả.
   terraform apply     →  Thực thi đúng bản kế hoạch đó
          ↓
   terraform destroy   →  Xoá sạch mọi thứ trong state
```

Cách đọc ký hiệu trong bản plan:

| Ký hiệu | Nghĩa |
| --- | --- |
| `+` | Tạo mới |
| `-` | Xoá |
| `~` | Sửa tại chỗ (không cần xoá) |
| `-/+` | **Xoá rồi tạo lại** — cảnh giác, mất dữ liệu nếu là database |

---

## 3. PHẦN A — Terraform + Docker (100% local, 0đ)

### 3.1. Đối chiếu với `docker-compose.yml`

Thư mục [terraform/](terraform/) dựng lại **đúng** stack ở buổi 5:

| docker-compose.yml | Terraform |
| --- | --- |
| `services.web` | `docker_container.web` |
| `services.db` | `docker_container.db` |
| `volumes.pgdata` | `docker_volume.pgdata` |
| mạng mặc định (tự có) | `docker_network.app` ← **phải khai báo tay** |
| `build: .` | `terraform_data.build_web_image` |
| `depends_on` | `depends_on` |
| `.env` | `variables.tf` + `terraform.tfvars` |

Điểm khác lớn nhất: **Compose tự tạo network, Terraform thì không.** Terraform
không làm gì ngầm — cái gì muốn có là phải viết ra. Đổi lại bạn nhìn file là
biết chính xác hệ thống gồm những gì.

### 3.2. Cấu trúc thư mục

```
terraform/
├── versions.tf              # Khai báo provider + phiên bản
├── variables.tf             # Tham số đầu vào (thay .env)
├── main.tf                  # Network, volume, image, container
├── outputs.tf               # Thông tin in ra sau khi apply
├── terraform.tfvars.example # Mẫu tham số (COMMIT được)
├── terraform.tfvars         # Tham số thật (KHÔNG commit)
└── .gitignore
```

### 3.3. Chạy thử

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

terraform init      # tải provider, ~30 giây lần đầu
terraform plan      # đọc kỹ bản kê trước khi apply
terraform apply     # gõ "yes" để xác nhận
```

Xong sẽ thấy:

```
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

web_url = "http://localhost:8081"
health_check_url = "http://localhost:8081/api/health"
```

Kiểm tra:

```bash
curl -s http://localhost:8081/api/health
# {"db":"connected","words":10}

curl -s http://localhost:8081/api/define/computer
# {"word":"computer","definition":"máy tính"}
```

> **Vì sao cổng 8081 chứ không phải 8080?**
> Container Jenkins của buổi 6 đang giữ 8080, stack `dictionary-prod` giữ 3000
> và 5432. Đây chính là lý do phải tham số hoá cổng: mỗi stack một cổng,
> chạy song song không đụng nhau. Đổi trong `terraform.tfvars` là xong.

### 3.4. Ba thí nghiệm để hiểu Terraform (làm thật, đừng chỉ đọc)

**Thí nghiệm 1 — Tính bất biến (idempotent)**

```bash
terraform apply    # lần 2
```

Kết quả: `No changes. Your infrastructure matches the configuration.`

Terraform so sánh thực tế với mong muốn, thấy khớp thì **không làm gì cả**.
Chạy 100 lần cũng ra 1 kết quả. `docker compose up` không đảm bảo điều này.

**Thí nghiệm 2 — Tự chữa lành (self-healing)**

```bash
docker rm -f dictionary-dev-web    # mô phỏng container chết
terraform apply                     # Terraform phát hiện và dựng lại
```

Kết quả: `Resources: 1 added` — nó chỉ dựng lại **đúng 1 container bị thiếu**,
không đụng db, network hay volume. Đây là "hội tụ trạng thái": bạn mô tả trạng
thái mong muốn, Terraform lo phần còn lại.

**Thí nghiệm 3 — Đổi tham số, xem plan**

Sửa `web_port = 8082` trong `terraform.tfvars` rồi:

```bash
terraform plan
```

Bạn sẽ thấy `-/+ destroy and then create replacement` — đổi cổng thì Docker
bắt buộc phải tạo lại container. Terraform nói trước cho bạn biết. Nếu đây là
database thật, dấu `-/+` là tín hiệu phải dừng lại suy nghĩ.

### 3.5. Hai lỗi thật đã gặp khi dựng bài này

Hai lỗi dưới đây **không phải tình huống giả định** — chúng xảy ra thật trong
lúc viết bài, và cách xử lý là phần đáng học nhất.

#### Lỗi 1: `archive/tar: invalid tar header`

```
Error: Error running legacy build: failed to read dockerfile:
archive/tar: invalid tar header
unpigz: skipping: <stdin>: corrupted -- invalid deflate data
```

**Nguyên nhân:** provider `kreuzwerker/docker` v3.9 nén build context bằng bộ
build **cũ** (legacy builder), còn Docker Engine 29 giải nén bằng `pigz`.
Hai bên không khớp.

**Đã thử và KHÔNG khắc phục được:** thêm `.dockerignore`, đặt
`build.version = "2"`, chuyển sang thư mục không có dấu cách. Lỗi vẫn còn —
kể cả với một `Dockerfile` chỉ có 2 dòng. Đây là lỗi tương thích giữa provider
và Engine 29, không phải lỗi code của mình.

**Cách xử lý:** để chính `docker build` (dùng BuildKit — luôn chạy được) build
image, Terraform chỉ điều phối:

```hcl
resource "terraform_data" "build_web_image" {
  triggers_replace = {
    dockerfile_hash = filesha256("${local.project_root}/Dockerfile")
    server_hash     = filesha256("${local.project_root}/backend/server.js")
  }

  provisioner "local-exec" {
    working_dir = local.project_root
    command     = "docker build -t ${local.name_prefix}-web:latest ."
  }
}

# Đọc lại image vừa build để lấy id thật
data "docker_image" "web" {
  name       = "${local.name_prefix}-web:latest"
  depends_on = [terraform_data.build_web_image]
}
```

Kỹ thuật này gọi là **escape hatch**: provider chưa hỗ trợ tốt thì gọi công cụ
gốc, phần còn lại vẫn để Terraform quản lý. Rất hay gặp trong thực tế.

> **Đánh đổi phải biết:** bước `local-exec` nằm ngoài tầm hiểu của Terraform —
> nó không "diff" được, chỉ chạy lại khi chuỗi băm trong `triggers_replace` đổi.
> Vì vậy phải liệt kê đúng các file nguồn cần theo dõi.

#### Lỗi 2: `port is already allocated`

```
Bind for 0.0.0.0:8080 failed: port is already allocated
```

Container Jenkins của buổi 6 đang giữ 8080. Cách tìm thủ phạm:

```bash
docker ps --format '{{.Names}}\t{{.Ports}}' | grep 8080
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

Vì `web_port` đã là biến nên chỉ cần sửa 1 dòng trong `terraform.tfvars`.
Nếu hardcode trong file `.tf` thì phải sửa code hạ tầng — đó là lý do
**mọi thứ có thể đổi đều nên là variable**.

### 3.6. Docker socket trên macOS

Provider Docker mặc định tìm `/var/run/docker.sock`, nhưng Docker Desktop trên
macOS để socket ở chỗ khác. Kiểm tra máy mình:

```bash
docker context inspect --format '{{.Endpoints.docker.Host}}'
```

| Công cụ | Đường dẫn socket |
| --- | --- |
| Docker Desktop (macOS) | `unix:///Users/<tên>/.docker/run/docker.sock` |
| OrbStack | `unix:///Users/<tên>/.orbstack/run/docker.sock` |
| Linux / Colima | `unix:///var/run/docker.sock` |

Sửa `docker_host` trong `terraform.tfvars` cho khớp.

---

## 4. PHẦN B — Terraform + AWS trên LocalStack (vẫn 0đ)

### 4.1. LocalStack là gì?

Một container dựng lên các API **y hệt AWS thật** (S3, IAM, Secrets Manager…)
nhưng chạy nội bộ trên máy bạn.

- Không cần tài khoản AWS, **không cần thẻ tín dụng**
- Không bao giờ phát sinh hoá đơn
- Gõ đúng cú pháp Terraform AWS như thật → học được kỹ năng dùng được
- Sai thì `docker compose down` là sạch

### 4.2. Điểm mấu chốt: chuyển hướng endpoint

Toàn bộ phần `resource` là cú pháp AWS **thật 100%**. Chỉ khối `provider` khác:

```hcl
provider "aws" {
  region     = var.aws_region
  access_key = "test"          # LocalStack không kiểm tra
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # Chuyển hướng MỌI service về localhost:4566
  endpoints {
    s3             = "http://localhost:4566"
    iam            = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
  }
}
```

Muốn deploy lên AWS thật: **xoá khối này, thay bằng credential thật.**
Không sửa một dòng `resource` nào. Đó là lý do học bằng LocalStack vẫn ra
kỹ năng dùng được.

### 4.3. Chạy thử

```bash
cd terraform-aws
docker compose -f docker-compose.localstack.yml up -d

# Chờ LocalStack sẵn sàng
curl -s http://localhost:4566/_localstack/health

terraform init
terraform apply
```

### 4.4. Bài này dựng những gì?

| Tài nguyên | Vai trò thực tế |
| --- | --- |
| `aws_s3_bucket` | Nơi lưu file backup database |
| `aws_s3_bucket_versioning` | Ghi đè nhầm vẫn phục hồi được |
| `aws_s3_bucket_public_access_block` | **Chặn public — nguyên nhân rò rỉ số 1 trên AWS** |
| `aws_secretsmanager_secret` | Cất mật khẩu đúng cách, thay cho `.env` |
| `aws_iam_role` + `aws_iam_policy` | Phân quyền: ai được làm gì |
| `aws_s3_object` | Upload thật `db/init.sql` lên bucket |

### 4.5. Kiểm chứng bằng aws-cli

```bash
EP=http://localhost:4566

# Xem file đã upload
aws --endpoint-url=$EP s3 ls s3://dictionary-dev-backup-000000000000/ --recursive
# 2026-09-28 09:06:03        808 schema/init.sql

# Versioning và mã hoá
aws --endpoint-url=$EP s3api get-bucket-versioning \
  --bucket dictionary-dev-backup-000000000000 --query Status --output text
# Enabled

# Đọc secret — CHÚ Ý phải có --region
aws --endpoint-url=$EP --region ap-southeast-1 \
  secretsmanager get-secret-value --secret-id dictionary-dev/database \
  --query SecretString --output text
# {"dbname":"tudien","host":"db","password":"DongA@2026",...}
```

> **Bẫy hay gặp:** thiếu `--region` khi gọi IAM/Secrets Manager sẽ báo
> `can't find the specified secret` dù secret vẫn tồn tại — vì ARN của chúng
> có gắn region. S3 thì không cần (ARN bucket không chứa region).

### 4.6. Giới hạn thật của LocalStack Community

Hai thứ trong bài này **không chạy được** trên bản miễn phí:

**a) ECR là tính năng bản Pro**

```
StatusCode: 501 ... api error InternalFailure:
API for service 'ecr' not yet implemented or pro feature
```

Phần ECR trong [terraform-aws/main.tf](terraform-aws/main.tf) đã được comment lại,
**giữ nguyên cú pháp đúng** để học và để dùng khi lên AWS thật. Muốn thực hành
registry miễn phí ngay bây giờ thì dùng GHCR của GitHub như buổi 6 — đó cũng là
lựa chọn thực tế cho dự án nhỏ.

**b) S3 lifecycle rule bị treo**

```
timeout while waiting for state to become 'true' (timeout: 3m0s)
```

LocalStack không trả lời API này, Terraform chờ 3 phút rồi bỏ cuộc.
Cũng đã comment lại kèm giải thích.

**Bài học:** LocalStack giả lập **phần lớn** chứ không phải **tất cả**.
Gặp lỗi 501 hoặc treo thì tra bảng hỗ trợ:
https://docs.localstack.cloud/references/coverage/

---

## 5. State file — phần nguy hiểm nhất, đọc kỹ

`terraform.tfstate` là sổ ghi chép của Terraform: nó ghi mọi tài nguyên đã tạo
và ID thật của chúng.

### Tuyệt đối KHÔNG commit `.tfstate`

**1. Bảo mật.** Mọi mật khẩu nằm ở dạng **chữ thường** trong file này, kể cả
biến đã đánh `sensitive = true`. Tự kiểm chứng:

```bash
grep -o 'DongA@2026' terraform/terraform.tfstate | head -1
```

`sensitive = true` chỉ che trong **log và output**, không mã hoá state.

**2. Xung đột.** Hai người cùng `apply` sẽ có 2 file state khác nhau, merge
không được, hạ tầng thành mồ côi — Terraform quên mất nó đã tạo cái gì.

Dự án thật giải quyết bằng **remote backend** (S3 + DynamoDB lock, hoặc
Terraform Cloud): state nằm trên mây, có khoá chống 2 người sửa cùng lúc.

### Ngược lại, PHẢI commit `.terraform.lock.hcl`

File này ghim chính xác phiên bản + chuỗi băm provider, giống `package-lock.json`.
Commit nó thì máy bạn, máy đồng đội và runner CI đều dùng đúng một phiên bản →
tránh cảnh "máy tôi chạy được mà".

---

## 6. Dọn dẹp

```bash
# Phần A
cd terraform && terraform destroy

# Phần B
cd terraform-aws && terraform destroy
docker compose -f docker-compose.localstack.yml down
```

---

## 7. Bài tập tự làm

| # | Đề bài | Gợi ý |
| --- | --- | --- |
| 1 | Dựng 2 môi trường dev + staging chạy song song | `terraform workspace new staging`, đổi `web_port` |
| 2 | Tách web+db thành `module/` dùng lại được | `module "app" { source = "./modules/app" }` |
| 3 | Thêm container pgAdmin vào stack | Thêm `docker_container` mới, nối vào `docker_network.app` |
| 4 | Đặt `prevent_destroy = true` cho volume rồi thử destroy | Xem Terraform chặn lại thế nào |
| 5 | Nối Terraform vào GitHub Actions có sẵn | `terraform plan` ở PR, `apply` khi merge vào main |
| 6 | Đẩy state lên remote backend | Dùng S3 của LocalStack làm backend |

---

## 8. So sánh 3 cách thực hành miễn phí

| | Terraform + Docker | LocalStack | AWS Free Tier |
| --- | --- | --- | --- |
| Chi phí | 0đ | 0đ | 0đ (12 tháng, **cần thẻ**) |
| Rủi ro hoá đơn | Không | Không | **Có** nếu quên `destroy` |
| Học cú pháp Terraform | ✅ | ✅ | ✅ |
| Học dịch vụ AWS | ❌ | ✅ (một phần) | ✅ đầy đủ |
| Tốc độ | Nhanh | Nhanh | Chậm (chờ AWS) |
| Hợp cho | **Bắt đầu** | Tập cú pháp AWS | Làm thật |

**Lộ trình khuyến nghị:** Phần A → Phần B → khi đã quen thì mở AWS Free Tier
(nhớ đặt billing alert và luôn `destroy` sau khi học xong).
