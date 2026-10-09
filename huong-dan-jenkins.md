# BÀI 2 — Jenkins: BUILD → TEST → PUSH → PULL → DEPLOY

> Mục tiêu: dựng Jenkins ngay trên laptop, chạy đủ 5 bước CI/CD, kết thúc bằng
> ứng dụng chạy thật ở http://localhost:3000 từ image kéo về từ registry.

---

## 1. Khác gì Bài 1?

Bài 1 dừng ở PUSH. Bài 2 đi tiếp hai bước cuối:

| Bước           | Bài 1 (Actions) | Bài 2 (Jenkins) |
| ---------------- | ---------------- | ---------------- |
| BUILD            | ✅               | ✅               |
| TEST             | ✅               | ✅               |
| PUSH             | ✅               | ✅               |
| **PULL**   | ❌               | ✅               |
| **DEPLOY** | ❌               | ✅               |

### Vì sao phải PULL khi image vừa build xong đang nằm sẵn trên máy?

Đây là câu hỏi hay nhất của bài này.

Nếu deploy bằng image local, bạn **không chứng minh được** image trên registry dùng
được. Lỡ push hỏng, lỡ thiếu layer, lỡ sai quyền — deploy vẫn chạy ngon trên máy bạn,
nhưng server thật kéo về sẽ chết.

Nên stage PULL cố tình `docker rmi` xoá bản local trước, rồi mới `docker pull`. Ép
Docker tải thật từ registry. Đó chính xác là việc server thật sẽ làm.

---

## 2. Kiến trúc: Jenkins trong container, deploy ra laptop

```
   ┌─────────────── LAPTOP (macOS, arm64) ────────────────┐
   │                                                       │
   │   ┌── container jenkins ──┐                           │
   │   │  Jenkins + docker CLI │                           │
   │   │                       │                           │
   │   │  docker build ────────┼──┐                        │
   │   │  docker compose up ───┼──┤                        │
   │   └───────────────────────┘  │                        │
   │              │               │ qua /var/run/docker.sock│
   │              │               ▼                        │
   │              │      ┌─── Docker Desktop ───┐          │
   │              │      │  (daemon thật)       │          │
   │              │      │                      │          │
   │              │      │  dictionary-prod-web ├──► :3000 │
   │              │      │  dictionary-prod-db  ├──► :5432 │
   │              │      └──────────────────────┘          │
   │              │                  ▲                     │
   │              └──────────────────┘                     │
   │           host.docker.internal (stage 6 gọi kiểm tra)  │
   └───────────────────────────────────────────────────────┘
                            │
                            ▼  push / pull
                     ghcr.io/<user>/dictionary-app-5
```

**Điểm mấu chốt:** container Jenkins **không** chạy Docker riêng bên trong. Nó chỉ có
`docker` CLI, điều khiển Docker Desktop của laptop qua socket `/var/run/docker.sock`
được mount vào. Kiểu này gọi là **DooD** (Docker outside of Docker).

Hệ quả quan trọng: image Jenkins build ra **nằm trên laptop**, và `docker compose up`
mở cổng **trên laptop** — mở http://localhost:3000 là thấy ngay.

---

## 3. Chuẩn bị

### 3.1. Tạo Personal Access Token để push lên GHCR

1. GitHub → Settings → Developer settings → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token (classic)**
3. Note: `jenkins-ghcr`, Expiration: 90 days
4. Tick đúng 2 quyền:
   - `write:packages`
   - `read:packages`
5. **Generate token** → **copy ngay** (chỉ hiện một lần)

### 3.2. Sửa tên tài khoản trong Jenkinsfile

Mở `Jenkinsfile`, dòng `IMAGE_NAME`:

```groovy
IMAGE_NAME = 'vuanhtuanvn85/test-devops'   // ĐỔI thành <tài khoản>/<repo> của bạn
```

> Bắt buộc **viết thường toàn bộ**. GHCR không nhận chữ hoa trong tên image.

Lấy đúng tên tài khoản bằng lệnh, tránh gõ nhầm:

```bash
gh api user --jq '.login | ascii_downcase'
```

> Sai tên tài khoản là lỗi khó đoán: token hợp lệ, đăng nhập thành công, nhưng
> stage PUSH báo `denied` vì bạn đang đẩy vào namespace của người khác.

---

## 4. Dựng Jenkins

```bash
cd "dictionary-app-5/jenkins"
docker compose up -d --build
```

Lần đầu mất ~3–5 phút (tải Jenkins + cài Docker CLI + plugin).

Mở http://localhost:8080 — vào thẳng giao diện, không hỏi mật khẩu
(đã tắt setup wizard cho đỡ mất bước học).

### Kiểm tra Jenkins gọi được Docker

```bash
docker exec jenkins docker version --format '{{.Server.Version}} / {{.Server.Arch}}'
```

Phải ra kiểu `29.7.2 / arm64`. Nếu báo `Cannot connect to the Docker daemon` → xem
mục Lỗi thường gặp bên dưới.

---

## 5. Tạo credential cho GHCR

Jenkins → **Manage Jenkins** → **Credentials** → **System** →
**Global credentials** → **Add Credentials**

| Trường | Giá trị                                                         |
| -------- | ----------------------------------------------------------------- |
| Kind     | **Username with password**                                  |
| Username | tên GitHub của bạn                                             |
| Password | **token** vừa tạo ở 3.1 (không phải mật khẩu GitHub) |
| ID       | `ghcr-credentials` ← **phải đúng chuỗi này**        |

ID phải khớp dòng `credentials('ghcr-credentials')` trong Jenkinsfile.

> Jenkinsfile khai `GHCR_CREDS = credentials(...)`. Jenkins tự tách thành hai biến
> `GHCR_CREDS_USR` và `GHCR_CREDS_PSW`. Pipeline đăng n	hập bằng `--password-stdin`
> nên token **không lộ** trong log.

---

## 6. Tạo pipeline job

Jenkins → **New Item** → tên `dictionary-cicd` → chọn **Pipeline** → OK

Trong phần **Pipeline**:

| Trường         | Giá trị                                                 |
| ---------------- | --------------------------------------------------------- |
| Definition       | **Pipeline script from SCM**                        |
| SCM              | **Git**                                             |
| Repository URL   | `https://github.com/<TÊN_GITHUB>/dictionary-app-5.git` |
| Branch Specifier | `*/main`                                                |
| Script Path      | `Jenkinsfile`                                           |

**Save**.

> Repo public thì để trống Credentials. Repo private thì thêm credential Git riêng.

---

## 7. Chạy và đọc kết quả

Bấm **Build Now**. Theo dõi ở **Console Output**.

### Stage Chuẩn bị

```
Image     : ghcr.io/<user>/dictionary-app-5:a1b2c3d
Máy này   : linux/arm64
Sẽ push   : linux/amd64,linux/arm64
```

Cài QEMU + tạo buildx builder. Lần đầu ~1 phút.

### Stage 1. BUILD

Build bản **arm64** (kiến trúc laptop) — native nên nhanh, không giả lập.
`--load` nạp vào Docker local để stage TEST dùng ngay.

### Stage 2. TEST

```
=== Chế độ: test image có sẵn -> ghcr.io/<user>/dictionary-app-5:a1b2c3d
  PASS  health báo đã kết nối DB
  PASS  health đếm đúng 10 từ
  ... (8 phép thử)
=== Kết quả: 8 đạt, 0 hỏng ===
```

Dòng `Chế độ: test image có sẵn` là bằng chứng **không build lại**.

### Stage 3. PUSH

Build đủ 2 kiến trúc rồi đẩy lên GHCR. Bản arm64 lấy từ cache (đúng layer vừa test),
chỉ amd64 phải build thêm qua QEMU (~1–2 phút).

Cuối stage in ra kiểm chứng:

```
linux/amd64
linux/arm64
```

### Stage 4. PULL

```
docker rmi ... → docker pull ...
Kiến trúc của image vừa kéo về: linux/arm64
```

Xoá local rồi kéo lại từ registry. Docker **tự chọn** arm64 cho laptop bạn — dù trên
registry có cả hai bản. Đó là multi-arch hoạt động.

### Stage 5. DEPLOY

`docker compose up -d` với `docker-compose.prod.yml` (dùng `image:`, không `build:`).

### Stage 6. Kiểm tra sau deploy

```
App sẵn sàng sau 2s
{"db":"connected","words":10}
{"word":"computer","definition":"máy tính"}
```

Mở **http://localhost:3000** — app chạy từ image đã đi trọn vòng
build → test → push → pull → deploy.

---

## 8. Bài tập kiểm chứng

### 8.1. CI chặn code hỏng, KHÔNG đụng app đang chạy

Sửa `db/init.sql` xoá bớt 1 dòng INSERT, commit, push, rồi **Build Now**.

Pipeline dừng ở stage 2:

```
  FAIL  health đếm đúng 10 từ
=== Kết quả: 7 đạt, 1 hỏng ===
```

Mở lại http://localhost:3000 — **vẫn chạy bình thường bản cũ**. Stage DEPLOY không
bao giờ được chạy. Đây là điều quan trọng nhất của CD: build hỏng thì production
không bị ảnh hưởng.

Khôi phục: `git revert HEAD && git push`

### 8.2. Rollback

Xem lịch sử build trong Jenkins, lấy SHA của bản chạy tốt trước đó:

```bash
cd "dictionary-app-5"
IMAGE_TAG=ghcr.io/<user>/dictionary-app-5:<sha_cũ> \
WEB_PORT=3000 DB_PORT=5432 \
POSTGRES_USER=dictuser POSTGRES_PASSWORD=dictpass POSTGRES_DB=dictionary \
docker compose -p dictionary-prod \
  -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Vài giây, không build lại gì. Đó là giá trị của tag bằng SHA.

### 8.3. Chứng minh image chạy được máy khác kiến trúc

Laptop bạn là arm64. Ép Docker chạy bản amd64 (giả lập):

```bash
docker pull --platform linux/amd64 ghcr.io/<user>/dictionary-app-5:latest
docker image inspect ghcr.io/<user>/dictionary-app-5:latest --format '{{.Architecture}}'
# => amd64
```

Cùng một tag, hai kiến trúc. Bạn bè dùng PC Intel hay Windows đều `docker pull` được.

### 8.4. Bật tự động chạy khi push code

Jenkinsfile đã khai `pollSCM('H/2 * * * *')` — Jenkins hỏi GitHub 2 phút/lần.

Bật: job → **Configure** → **Build Triggers** → tick **Poll SCM** → Save.

> Laptop không có IP public nên GitHub **không gọi webhook vào được**. Poll là cách
> đúng cho môi trường học. Server thật có IP public thì dùng webhook (nhanh hơn,
> không tốn request rỗng).

---

## 9. Lỗi thường gặp

| Lỗi                                    | Nguyên nhân                           | Cách sửa                                                                                                                                                                                                                |
| --------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Cannot connect to the Docker daemon` | Chưa mount socket, hoặc sai group     | Kiểm tra`jenkins/docker-compose.yml` có dòng `/var/run/docker.sock:/var/run/docker.sock` và `group_add: ["0"]`. Trên **Linux** đổi `"0"` thành kết quả của `stat -c '%g' /var/run/docker.sock` |
| `docker: not found` trong pipeline    | Dùng image`jenkins/jenkins` gốc     | Phải`docker compose up -d --build` để dùng `jenkins/Dockerfile` đã cài docker CLI                                                                                                                              |
| `denied` khi push                     | Token thiếu quyền / sai credential ID | Token phải có`write:packages`. Credential ID phải đúng `ghcr-credentials`                                                                                                                                        |
| `invalid reference format`            | `IMAGE_NAME` có chữ HOA             | Viết thường toàn bộ                                                                                                                                                                                                  |
| Stage 6 timeout                         | Jenkins không gọi ra host được     | `docker exec jenkins getent hosts host.docker.internal` phải ra IP. Trên Linux thêm `extra_hosts: ["host.docker.internal:host-gateway"]` vào `jenkins/docker-compose.yml`                                       |
| Port 3000 bị chiếm                    | Stack cũ còn chạy                    | `docker compose -p dictionary-prod -f docker-compose.yml -f docker-compose.prod.yml down`                                                                                                                               |
| Build amd64 rất lâu                   | QEMU giả lập                          | Bình thường lần đầu (~2 phút). Lần sau có cache nhanh hơn nhiều                                                                                                                                                |
| `no space left on device`             | Image cũ chất đống                  | `docker system prune -a --volumes` (xoá sạch, cẩn thận)                                                                                                                                                             |
| Port 8080 bị chiếm lúc dựng Jenkins | Tiến trình khác giữ cổng | Tìm thủ phạm: `lsof -nP -iTCP:8080 -sTCP:LISTEN`. Là container Jenkins cũ → `docker rm -f jenkins`. Là app khác cần giữ → đổi thành `"8090:8080"` trong `jenkins/docker-compose.yml` |
| Jenkins báo `Up` nhưng `localhost:8080` không vào được | Lần tạo container trước lỗi networking; lần sau chỉ **start lại** container hỏng | Dấu hiệu: `docker ps` cột PORTS thiếu `0.0.0.0:8080->`. Sửa: `docker compose down` rồi `up -d` — phải **tạo lại**, start lại không đủ |
| `mkdir /tmp/...: permission denied` lúc build | Cache ghi ra thư mục local | Đã sửa trong Jenkinsfile: dùng `type=registry`. Builder `docker-container` chạy trong container BuildKit **riêng**, `/tmp` của nó không phải `/tmp` của Jenkins; volume mount vào lại thuộc `root` nên user `jenkins` không ghi được |
| `ERROR: exporting cache to registry` ở lần chạy đầu | Chưa có tag `:buildcache` trên GHCR | Bỏ qua được. `ignore-error=true` giữ cho build vẫn thành công (exit code 0). Lần chạy sau hết báo |
| `denied` lúc push dù token đúng | `IMAGE_NAME` sai tên tài khoản | Phải khớp **chính xác** tên GitHub, viết thường. Kiểm tra: `gh api user --jq .login` |

---

## 10. Dọn dẹp sau khi học xong

```bash
# Dừng app
cd "dictionary-app-5"
docker compose -p dictionary-prod -f docker-compose.yml -f docker-compose.prod.yml down

# Dừng Jenkins (giữ dữ liệu job)
cd jenkins && docker compose down

# Xoá luôn cả dữ liệu Jenkins
docker compose down -v
```

---

## 11. So sánh hai bài

|                  | Bài 1 — Actions                        | Bài 2 — Jenkins                      |
| ---------------- | ---------------------------------------- | -------------------------------------- |
| Chạy ở đâu   | Máy ảo GitHub                          | Container trên laptop                 |
| Thời gian dựng | ~5 phút                                 | ~30 phút                              |
| Kích hoạt      | Tự động khi push                      | Poll 2 phút/lần                      |
| Kết thúc ở    | Image trên registry                     | App chạy thật ở localhost:3000      |
| Chi phí         | Miễn phí (public repo)                 | Điện laptop                          |
| Vai trò         | **CI** — gác cổng chất lượng | **CD** — đưa lên chạy thật |

Cả hai dùng chung: `Dockerfile`, `docker-compose.prod.yml`, `scripts/smoke-test.sh`.
Viết một lần, hai công cụ cùng dùng — đó là dấu hiệu pipeline được thiết kế tốt.
