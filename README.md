# test-devops — Ứng dụng từ điển

Ứng dụng web tra từ điển Anh–Việt. Dùng làm bài thực hành DevOps: đóng gói bằng Docker, build và đẩy image tự động bằng GitHub Actions.

**Thành phần:** React (Vite) → build tĩnh → Express phục vụ → PostgreSQL.

---

## Yêu cầu

- Docker Desktop (đã bật, kiểm tra bằng `docker version`)
- Git

Không cần cài Node.js ở máy — mọi thứ chạy trong container.

---

## Chạy nhanh

```bash
git clone https://github.com/vuanhtuanvn85/test-devops.git
cd test-devops
docker compose up --build -d
```

Mở **http://localhost:&lt;WEB_PORT&gt;** — thay `<WEB_PORT>` bằng giá trị trong `.env`.

Không nhớ cổng thì xem bằng:

```bash
docker compose ps        # cột PORTS hiện 0.0.0.0:<WEB_PORT>->3000/tcp
```

Bên trong container web luôn nghe cổng `3000`; `WEB_PORT` chỉ là cổng ánh xạ ra máy host.

---

## Cấu hình

Mọi thông số nằm trong `.env`, được `docker-compose.yml` đọc tự động.

| Biến | Ý nghĩa |
|---|---|
| `POSTGRES_USER` | User database |
| `POSTGRES_PASSWORD` | Mật khẩu database |
| `POSTGRES_DB` | Tên database |
| `WEB_PORT` | Cổng web mở ra máy host |
| `DB_PORT` | Cổng Postgres mở ra host (để xem bằng DBeaver/pgAdmin) |

Máy mới chưa có `.env` thì tạo từ mẫu rồi sửa giá trị:

```bash
cp .env.example .env
```

Xem giá trị đang dùng:

```bash
cat .env
```

> **Dự án thật phải đưa `.env` vào `.gitignore`** và không bao giờ commit mật khẩu.

---

## Hai cách chạy

Có hai cách, khác nhau ở chỗ image đến từ đâu.

### Cách A — Build từ source (khi đang sửa code)

```bash
docker compose up --build -d
```

Docker đọc `Dockerfile`, build image ngay tại máy. Dùng khi bạn vừa sửa code và muốn thấy kết quả.

`--build` bắt build lại. Không sửa gì thì `docker compose up -d` là đủ (nhanh hơn).

### Cách B — Dùng image có sẵn từ GHCR (khi chỉ muốn chạy)

```bash
docker compose -f docker-compose.yml -f docker-compose.ghcr.yml up -d
```

Kéo image mà GitHub Actions đã build sẵn về chạy, không build lại. Nhanh hơn nhiều vì bỏ qua toàn bộ `npm install` + `npm run build`.

Phải truyền **hai** file `-f`. Compose gộp chúng theo thứ tự, file sau đè file trước: `docker-compose.ghcr.yml` chỉ đè đúng phần `web` (thay `build: .` thành `image: ghcr.io/...`), phần `db` giữ nguyên từ file gốc.

| | Cách A (build) | Cách B (GHCR) |
|---|---|---|
| Nguồn image | Dockerfile ở máy | Registry GHCR |
| Thời gian | Vài phút (lần đầu) | Vài chục giây |
| Dùng khi | Đang phát triển | Chạy thử, demo, deploy |

---

## Các lệnh hay dùng

```bash
# Xem trạng thái
docker compose ps

# Xem log (Ctrl+C để thoát, container vẫn chạy)
docker compose logs -f
docker compose logs web          # riêng service web
docker compose logs db

# Dừng — GIỮ dữ liệu database
docker compose down

# Dừng — XOÁ luôn dữ liệu database
docker compose down -v

# Vào thẳng Postgres kiểm tra dữ liệu
# (nạp .env vào shell trước để không phải gõ tay user/db name)
set -a && source .env && set +a
docker compose exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM words;"
```

Phân biệt `down` và `down -v` rất quan trọng — xem phần [Lưu ý](#lưu-ý-quan-trọng) bên dưới.

Với cách B, nhớ kèm hai cờ `-f` ở mọi lệnh:

```bash
docker compose -f docker-compose.yml -f docker-compose.ghcr.yml down
```

---

## Kiểm tra hoạt động

```bash
# Nạp .env để dùng $WEB_PORT, khỏi gõ cổng bằng tay
set -a && source .env && set +a

curl http://localhost:$WEB_PORT/api/health
# {"db":"connected","words":10}

curl http://localhost:$WEB_PORT/api/words
# ["apple","book","computer",...]

curl http://localhost:$WEB_PORT/api/define/apple
# {"word":"apple","definition":"quả táo"}
```

`/api/health` trả `db: connected` nghĩa là web đã nối được Postgres — đây là điểm hay hỏng nhất.

Hoặc chạy bộ smoke test đầy đủ (8 kiểm tra). Script tự dựng một stack riêng ở cổng khác, kiểm tra xong tự dọn — chạy song song được với stack đang mở:

```bash
# Build từ source rồi test
./scripts/smoke-test.sh

# Hoặc test một image có sẵn, không build lại (cách CI dùng)
SMOKE_IMAGE=ghcr.io/vuanhtuanvn85/test-devops/web:latest ./scripts/smoke-test.sh
```

Thoát mã `0` = tất cả đạt.

---

## Pipeline CI/CD

### Vòng đời một thay đổi

```
Sửa code  →  git push origin main  →  GitHub Actions  →  image trên GHCR  →  máy khác pull về chạy
```

### Workflow làm gì

File [`.github/workflows/build-test-push.yml`](.github/workflows/build-test-push.yml), chạy khi push vào `main` (hoặc bấm tay ở tab **Actions** → **Run workflow**).

Pipeline chia **3 job** nối tiếp nhau:

```
build  ──►  test  ──►  push
```

| Job | Việc | Chờ job |
|---|---|---|
| `build` | Build image → lưu thành `image.tar` → upload artifact | — |
| `test` | Tải artifact → `docker load` → smoke test **chính image đó** | `build` |
| `push` | Build bản đa kiến trúc → đẩy lên GHCR | `test` |

Test hỏng → job `push` bị bỏ qua, **GHCR không nhận image lỗi**.

Điểm mấu chốt của việc tách job: image được test **đúng là** image sẽ deploy. Bản một job trước đây build hai lần (một lần để test, một lần để push) nên hai image đó về lý thuyết có thể khác nhau.

### Hai điều dễ vấp

**1. Mỗi job chạy trên một máy ảo RIÊNG.** Job sau không thấy file của job trước — kể cả code đã checkout. Vì vậy job nào cũng phải `actions/checkout` lại, và muốn chuyển image giữa job phải dùng artifact (`upload-artifact` / `download-artifact`). GitLab tự lo việc này giữa các stage; GitHub bắt khai báo tường minh.

**2. Job `push` vẫn phải build lại.** Tarball **không chứa được manifest list** (một tag gộp nhiều kiến trúc) — định dạng đó chỉ tồn tại trên registry. Nên job `build` chỉ tạo bản `amd64` để test, còn bản đa kiến trúc phải build và push thẳng.

Chi phí này được giảm bằng `cache-from: type=gha`: layer `amd64` lấy lại từ cache của job `build`, chỉ phần `arm64` là thực sự tốn công.

> Hệ quả cần biết: **bản `arm64` chưa từng được smoke test** — runner là `amd64`, chạy test trên `arm64` phải qua giả lập QEMU, rất chậm.

### Về QEMU và Buildx

Job `push` cần **cả hai**, thiếu một là hỏng:

| Action | Vai trò |
|---|---|
| `setup-qemu-action` | Giả lập CPU để chạy binary khác kiến trúc |
| `setup-buildx-action` | Tạo builder `docker-container` — driver duy nhất gộp được nhiều kiến trúc vào một tag |

Thiếu Buildx sẽ báo:

```
ERROR: Multi-platform build is not supported for the docker driver.
```

### Image tạo ra

Mỗi lần chạy đẩy lên **hai tag** cùng trỏ vào một image:

```
ghcr.io/vuanhtuanvn85/test-devops/web:latest
ghcr.io/vuanhtuanvn85/test-devops/web:<git-sha>
```

| Tag | Đặc điểm | Dùng khi |
|---|---|---|
| `latest` | **Đổi mỗi lần push main** | Muốn luôn chạy bản mới nhất |
| `<git-sha>` | **Không bao giờ đổi** | Deploy thật, hoặc cần tái lập đúng một bản |

Muốn cố định phiên bản, sửa dòng `image:` trong `docker-compose.ghcr.yml` thành tag SHA.

### Đa kiến trúc

Image build cho `linux/amd64` và `linux/arm64`. Cùng một tag, Docker tự chọn đúng bản cho máy:

```bash
docker image inspect ghcr.io/vuanhtuanvn85/test-devops/web:latest \
  --format '{{.Os}}/{{.Architecture}}'
# Mac M-series  → linux/arm64
# Server Linux  → linux/amd64
```

---

## Làm việc với image trên GHCR

```bash
# Kéo về
docker pull ghcr.io/vuanhtuanvn85/test-devops/web:latest

# Cập nhật khi CI vừa push bản mới
docker compose -f docker-compose.yml -f docker-compose.ghcr.yml pull
docker compose -f docker-compose.yml -f docker-compose.ghcr.yml up -d
```

Package đang để **Public** nên không cần đăng nhập. Nếu đổi sang Private:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u vuanhtuanvn85 --password-stdin
```

Token cần scope `read:packages`.

---

## Lưu ý quan trọng

**`db/init.sql` chỉ chạy một lần duy nhất.** Postgres nạp file này lúc khởi tạo, khi volume `pgdata` còn rỗng. Sửa `init.sql` rồi `up` lại sẽ **không thấy gì thay đổi**. Muốn áp dụng:

```bash
docker compose down -v      # xoá volume
docker compose up -d        # Postgres khởi tạo lại từ đầu
```

Lệnh này **xoá sạch dữ liệu**. Cân nhắc trước khi chạy.

**Container gọi nhau bằng tên service, không phải `localhost`.** Web nối database qua `DB_HOST: db` — `db` là tên service trong `docker-compose.yml`, Compose tạo sẵn DNS nội bộ. Trong mạng container, `localhost` là chính container đó.

**Web chờ database sẵn sàng rồi mới khởi động.** Nhờ `depends_on: condition: service_healthy` kết hợp healthcheck `pg_isready`, không bị lỗi "connection refused" lúc boot.

---

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `bind: address already in use` | Cổng đang bị chiếm | Sửa `WEB_PORT`/`DB_PORT` trong `.env`, `up` lại |
| `curl localhost:3000` không phản hồi | Nhầm cổng | Cổng host là `WEB_PORT` trong `.env`, không phải `3000` — xem `docker compose ps` |
| `{"db":"disconnected"}` | Web chưa nối được db | `docker compose logs db`, `docker compose ps` xem db có `healthy` không |
| Sửa `init.sql` mà không thấy đổi | Volume đã có dữ liệu | `docker compose down -v` rồi `up` |
| Biến `${...}` rỗng khi `up` | Thiếu `.env` | `cp .env.example .env` |
| CI lỗi *Multi-platform not supported* | Thiếu bước Buildx | Thêm `docker/setup-buildx-action@v3` trước bước build |
| `container name is already in use` | `container_name` cố định là duy nhất trên toàn máy, làm vô hiệu cờ `-p` của Compose | File đè phải có `container_name: !reset null` (xem `docker-compose.prod.yml`) |

---

## Cấu trúc thư mục

```
.
├── .github/workflows/
│   └── build-test-push.yml     # CI: build → test → push GHCR
├── backend/
│   ├── server.js               # Express + API + phục vụ file tĩnh
│   ├── db.js                   # Kết nối PostgreSQL
│   └── package.json
├── frontend/
│   ├── src/App.jsx             # Giao diện React
│   └── vite.config.js
├── db/
│   └── init.sql                # Tạo bảng + dữ liệu mẫu (chạy lần đầu)
├── scripts/
│   └── smoke-test.sh           # Dựng stack + kiểm tra API
├── Dockerfile                  # Build 2 stage: frontend → backend
├── docker-compose.yml          # Chạy từ source
├── docker-compose.ghcr.yml     # File đè: chạy image :latest từ GHCR
├── docker-compose.prod.yml     # File đè: chạy image theo biến $IMAGE_TAG (CI dùng)
├── .env                        # Cấu hình thật
└── .env.example                # Mẫu cấu hình
```

**Ba file compose** làm ba việc khác nhau. `docker-compose.yml` là gốc, hai file kia là **file đè** — luôn dùng kèm file gốc, không thay thế nó:

| File | Nguồn image | Dùng khi |
|---|---|---|
| `docker-compose.yml` | Build từ `Dockerfile` | Đang sửa code |
| `docker-compose.ghcr.yml` | `ghcr.io/.../web:latest` (ghi cứng) | Chạy tay bản mới nhất |
| `docker-compose.prod.yml` | Biến `$IMAGE_TAG` | CI, hoặc cố định một phiên bản |

`Dockerfile` dùng **multi-stage build**: stage 1 build React, stage 2 chỉ lấy thư mục `dist` đã build sang image backend. Toolchain của Vite không lọt vào image cuối, nên image nhẹ hơn nhiều.

---

## API

| Method | Endpoint | Trả về |
|---|---|---|
| `GET` | `/api/health` | `{"db":"connected","words":10}` |
| `GET` | `/api/words` | Mảng tất cả từ, sắp xếp A→Z |
| `GET` | `/api/define/:word` | `{"word":...,"definition":...}` hoặc 404 |
