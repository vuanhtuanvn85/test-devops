# BÀI 1 — GitHub Actions: BUILD → TEST → PUSH

> Mục tiêu: mỗi lần push code, GitHub tự build image đa kiến trúc, chạy smoke test,
> và đẩy lên GitHub Container Registry (GHCR). Không cần cài gì trên máy.

---

## 1. Nguyên tắc cần hiểu trước khi làm

### Nguyên tắc 1 — Build đúng một lần

Sai lầm kinh điển của người mới:

```
Actions: build image → test  ✅ đạt
Jenkins: build image LẦN NỮA → deploy
```

Hai image đó **không đảm bảo giống nhau**: `npm install` có thể kéo version mới hơn,
base image `node:20-alpine` có thể đã được cập nhật. Bạn test một image nhưng deploy
một image khác — bug lọt qua CI mà không ai biết vì sao.

Cách làm đúng trong bài này:

```
build 1 lần → test CHÍNH image đó → push CHÍNH image đó
```

### Nguyên tắc 2 — Image chạy được mọi máy (multi-arch)

Máy bạn là Mac M-series (`arm64`). Runner của GitHub là `amd64`. Nếu chỉ build amd64,
Mac của bạn pull về sẽ phải giả lập — chậm, và đôi khi lỗi.

Giải pháp: Buildx đẩy lên một **manifest list** — cùng một tag chứa cả hai bản:

```
ghcr.io/user/dictionary-app-5:abc1234
   ├── linux/amd64   ← PC Intel/AMD, server cloud, Docker Desktop Windows/Linux
   └── linux/arm64   ← Mac M1/M2/M3, Raspberry Pi, AWS Graviton
```

Người dùng chỉ gõ `docker pull`, Docker **tự chọn** đúng bản cho máy họ.

> App này thuần JavaScript, không có thư viện biên dịch native (đã kiểm tra
> `package-lock.json`), nên code chạy y hệt trên cả hai kiến trúc. Vì vậy test trên
> amd64 là đủ tin cậy. Nếu sau này thêm thư viện native (`bcrypt`, `sharp`...),
> phải test riêng từng kiến trúc.

### Nguyên tắc 3 — Tag bằng git SHA, không chỉ `latest`

`latest` là con trỏ di động: hôm nay trỏ commit A, mai trỏ commit B. Không rollback
được, không biết server đang chạy code nào.

Workflow đẩy **2 tag** cho mỗi lần build:
- `:abc1234` — 7 ký tự đầu của commit SHA. Bất biến. Dùng để deploy và rollback.
- `:latest` — cho tiện tra cứu thủ công.

---

## 2. Luồng chạy

```
   push code lên GitHub
           │
           ▼
   ┌───────────────────────────────────┐
   │  Runner ubuntu-latest (amd64)     │
   │                                   │
   │  0. checkout                      │
   │  1. BUILD amd64  ──┐  (--load)    │
   │  2. TEST ──────────┘              │   ← test chính image vừa build
   │     smoke-test.sh: 8 phép thử     │
   │         │                         │
   │      đạt? ──── không ──► DỪNG ❌  │   ← không push image hỏng
   │         │ có                      │
   │  3. PUSH amd64 + arm64 ───────────┼──► ghcr.io/user/app:abc1234
   │     (dùng lại cache bước 1)       │                      :latest
   └───────────────────────────────────┘
```

Điểm cần chú ý: bước 1 build `--load` (nạp vào Docker local) nên **chỉ được 1 kiến trúc** —
đó là giới hạn của Docker, không phải lựa chọn. Bản đa kiến trúc chỉ tạo được khi đẩy
thẳng lên registry ở bước 3. Nhờ cache, bản amd64 ở bước 3 lấy nguyên layer đã test,
chỉ bản arm64 phải build thêm.

---

## 3. Các bước thực hành

### Bước 1 — Đưa code lên GitHub

Project hiện chưa phải git repo. Khởi tạo:

```bash
cd "dictionary-app-5"

git init
git add .
git commit -m "Buổi 5: dictionary app + CI/CD"
```

> `.gitignore` đã loại `.env` — file chứa mật khẩu **không** được lên GitHub.
> Kiểm tra lại cho chắc: `git status --short | grep .env` phải không ra gì.

Tạo repo trên GitHub rồi:

```bash
git remote add origin https://github.com/<TÊN_GITHUB>/dictionary-app-5.git
git branch -M main
git push -u origin main
```

### Bước 2 — Kiểm tra workflow đã có

Project có **hai** workflow, chia vai theo giai đoạn của code:

| File | Khi nào chạy | Vai trò | Push image? |
|---|---|---|---|
| `ci.yml` | Mở/cập nhật Pull Request | Gác cổng — chặn code hỏng vào main | ❌ |
| `build-test-push.yml` | Push vào `main`, hoặc bấm nút | Tạo image thật | ✅ |

Hai file **không bao giờ chạy cùng lúc**, nên không tốn phút chạy trùng và không
đẩy hai bộ image giống nhau.

Cả hai không cần sửa gì: tên image tự lấy từ `github.repository`, token tự do
GitHub cấp.

#### Vòng đời một thay đổi code

```
  tạo nhánh, sửa code
          │
          ▼
  mở Pull Request ──────────► ci.yml chạy
          │                     build 1 lần → test
          │                     hỏng? PR bị chặn, KHÔNG merge được
          │                     đạt?  hiện dấu ✅ trên PR
          ▼
     bấm Merge
          │
          ▼
  code vào main ────────────► build-test-push.yml chạy
                                test → build đa kiến trúc → push GHCR
                                          │
                                          ▼
                                 ghcr.io/.../web:latest
                                                 :<sha>
```

Ý nghĩa: PR được kiểm tra **trước khi** vào main, còn image chỉ được tạo từ code
**đã qua kiểm tra và đã merge**. Registry không bao giờ chứa image của code chưa
ai duyệt.

#### Hai file khác nhau ở đâu?

|  | ci.yml | build-test-push.yml |
|---|---|---|
| Smoke test | ✅ | ✅ |
| Số lần build | **1 lần** | **2 lần** |
| Image test = image push | ✅ | ❌ không đảm bảo |
| Multi-arch | ❌ (không cần) | ✅ |
| Quyền xin | chỉ `contents: read` | thêm `packages: write` |
| Độ dài | ~100 dòng | ~75 dòng, dễ đọc hết |

Hai dòng đáng chú ý:

**"Số lần build"** — `build-test-push.yml` gọi `smoke-test.sh` không kèm biến
`SMOKE_IMAGE`, nên script **tự build từ source** (image A), rồi bước cuối build
lại lần nữa để push (image B). Bạn test A nhưng push B. Thực tế A và B hầu như
luôn giống nhau, nhưng "hầu như" không phải "chắc chắn": `npm install` có thể kéo
bản vá mới, `node:20-alpine` có thể đã cập nhật giữa hai lần build.

`ci.yml` tránh hẳn rủi ro đó: build một lần, rồi truyền `SMOKE_IMAGE` để test
đúng image vừa build. Trong log bạn sẽ thấy hai dòng khác nhau:

```
ci.yml              →  === Chế độ: test image có sẵn -> ghcr.io/...
build-test-push.yml →  === Chế độ: build từ source
```

**"Multi-arch"** — `ci.yml` chỉ build amd64 vì PR chỉ cần biết code chạy đúng hay
không; app này thuần JavaScript nên kết quả giống nhau trên mọi kiến trúc. Build
thêm arm64 ở bước gác cổng chỉ tốn thời gian mà không phát hiện thêm lỗi. Bản đa
kiến trúc để dành cho `build-test-push.yml`, nơi tạo image thật.

> Muốn chạy tay bản nào: tab **Actions** → chọn tên workflow bên trái →
> nút **Run workflow**. Cả hai đều có `workflow_dispatch`.

### Bước 3 — Xem `build-test-push.yml` chạy

Push ở bước 1 vào `main` sẽ kích hoạt nó ngay.
Vào repo trên GitHub → tab **Actions** → chọn lần chạy mới nhất.

| Step | Thời gian | Ý nghĩa |
|---|---|---|
| Checkout code | ~2s | Tải code về runner |
| Login to GHCR | ~1s | Dùng `GITHUB_TOKEN` có sẵn |
| **Smoke test** | ~90s | Build từ source + chạy 8 phép thử |
| Set up QEMU | ~5s | Cài giả lập để build arm64 |
| Build and push | ~120s (lần đầu) | Build amd64 + arm64, đẩy lên GHCR |

> Bước Smoke test đặt **trước** Build and push. Test hỏng thì job dừng,
> image không bao giờ lên registry.

### Bước 4 — Đọc kết quả TEST

Mở step **Smoke test**, phải thấy:

```
=== Chế độ: build từ source
=== Dựng stack (cổng 3999) ===
=== Chờ web sẵn sàng ===
  sẵn sàng sau 6s
=== Kiểm tra API ===
  PASS  health báo đã kết nối DB
  PASS  health đếm đúng 10 từ
  PASS  danh sách từ có 'computer'
  PASS  tra 'computer' ra nghĩa tiếng Việt
  PASS  tra chữ hoa 'APPLE' vẫn ra kết quả
  PASS  từ không tồn tại trả HTTP 404
  PASS  trang chủ trả HTTP 200
  PASS  database có bảng words
=== Kết quả: 8 đạt, 0 hỏng ===
```

Dòng đầu `Chế độ: build từ source` chính là **lần build thứ nhất** đã nói ở trên.
Khi chạy `ci.yml` (trên PR) dòng này sẽ là `Chế độ: test image có sẵn` — đó là
khác biệt giữa hai file, nhìn thấy trực tiếp trong log.

### Bước 5 — Xem image trên GHCR

Trang repo GitHub → cột phải, mục **Packages** → `dictionary-app-5/web`.

Hoặc xem bằng lệnh — không cần đăng nhập nếu package để public:

```bash
docker buildx imagetools inspect ghcr.io/<TÊN_GITHUB>/dictionary-app-5/web:latest
```

Phải thấy cả hai kiến trúc:

```
Manifests:
  Platform: linux/amd64
  Platform: linux/arm64
```

> Tên image có `/web` ở cuối vì `build-test-push.yml` khai
> `IMAGE_NAME: ghcr.io/${{ github.repository }}/web`. Đây là package con —
> tiện nếu sau này tách thêm image khác (worker, cron...).

### Bước 6 — Kéo image về máy và chạy thử

```bash
docker pull ghcr.io/<TÊN_GITHUB>/dictionary-app-5/web:latest

# Xác nhận Docker tự chọn đúng arm64 cho máy Mac của bạn
docker image inspect ghcr.io/<TÊN_GITHUB>/dictionary-app-5/web:latest \
  --format '{{.Os}}/{{.Architecture}}'
# => linux/arm64
```

Chạy thật bằng image vừa kéo (không build lại):

```bash
IMAGE_TAG=ghcr.io/<TÊN_GITHUB>/dictionary-app-5/web:latest \
WEB_PORT=3000 DB_PORT=5432 \
POSTGRES_USER=dictuser POSTGRES_PASSWORD=dictpass POSTGRES_DB=dictionary \
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Mở http://localhost:3000 — đây chính là image GitHub đã build và test.

Dọn dẹp:
```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
```

---

## 4. Bài tập kiểm chứng

### 4.1. Thấy `ci.yml` gác cổng Pull Request

Tạo nhánh và **cố tình làm hỏng** — xoá bớt 1 dòng INSERT trong `db/init.sql`
(còn 9 từ thay vì 10):

```bash
git checkout -b thu-lam-hong
# sửa db/init.sql, xoá 1 dòng INSERT
git commit -am "test: thử làm hỏng"
git push -u origin thu-lam-hong
```

Mở Pull Request trên GitHub. `ci.yml` chạy ngay trong PR, và phải thấy:

```
  FAIL  health đếm đúng 10 từ
        mong đợi chứa: "words":10
        nhận được:     {"db":"connected","words":9}
=== Kết quả: 7 đạt, 1 hỏng ===
```

PR hiện dấu ❌ đỏ. Hai điều quan trọng xảy ra:

1. **Code hỏng chưa vào `main`** — bạn thấy lỗi trước khi merge
2. **`build-test-push.yml` chưa hề chạy** — nó chỉ kích hoạt khi push vào `main`,
   mà code này còn nằm ở nhánh riêng. Registry hoàn toàn sạch.

Đây chính là lý do tách hai file.

Sửa lại cho đúng rồi push tiếp lên cùng nhánh → `ci.yml` tự chạy lại → PR chuyển ✅.
Lúc đó bấm **Merge** → `build-test-push.yml` mới chạy và đẩy image lên GHCR.

Dọn: `git checkout main && git branch -D thu-lam-hong`

### 4.2. So sánh log hai workflow

Chạy tay cả hai (tab Actions → chọn workflow → **Run workflow**), rồi mở bước test
của mỗi bên. Dòng đầu tiên khác nhau:

| Workflow | Dòng đầu trong log test | Nghĩa là |
|---|---|---|
| `ci.yml` | `=== Chế độ: test image có sẵn -> ghcr.io/...` | build 1 lần, test đúng image đó |
| `build-test-push.yml` | `=== Chế độ: build từ source` | script tự build → build lần 2 ở bước push |

Đây là cách nhìn thấy trực tiếp sự khác biệt đã mô tả ở mục 3, không phải tin lời
tài liệu.

### 4.3. Rollback bằng tag SHA

```bash
# Xem các tag đã có: trang repo → Packages → dictionary-app-5/web
# Chạy lại bản cũ (thay <sha_cũ> bằng SHA đầy đủ 40 ký tự):
IMAGE_TAG=ghcr.io/<TÊN_GITHUB>/dictionary-app-5/web:<sha_cũ> \
WEB_PORT=3000 DB_PORT=5432 \
POSTGRES_USER=dictuser POSTGRES_PASSWORD=dictpass POSTGRES_DB=dictionary \
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Đây là lý do tag bằng SHA: rollback chỉ là đổi một chuỗi, không cần build lại gì.

> `build-test-push.yml` dùng `${{ github.sha }}` nên tag dài 40 ký tự. Muốn ngắn
> gọn hơn thì rút còn 7 ký tự như `ci.yml` đang làm — không bắt buộc, chỉ tiện hơn
> khi gõ tay.

---

## 5. Lỗi thường gặp

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| `denied: permission_denied` khi push | Thiếu quyền packages | Workflow đã có `permissions: packages: write`. Nếu vẫn lỗi: Settings → Actions → General → Workflow permissions → chọn **Read and write** |
| `invalid reference format` | Tên GitHub có chữ HOA | Workflow đã tự `tr '[:upper:]' '[:lower:]'`. Tên image GHCR bắt buộc viết thường |
| TEST timeout sau 30s | Postgres khởi động chậm | Xem log ngay dưới dòng TIMEOUT. Thường do `init.sql` sai cú pháp |
| Không thấy tab Packages | Package đang private | Bình thường. Vào package → Settings → đổi visibility nếu muốn public |
| Build arm64 rất lâu | QEMU giả lập chậm | Bình thường ở lần đầu (~2 phút). Lần sau có cache sẽ nhanh |

---

## 6. Tóm tắt vai trò

Sau bài này, GitHub Actions đảm nhiệm:

| Việc | `ci.yml` (PR) | `build-test-push.yml` (main) |
|---|---|---|
| Build image | ✅ 1 lần, amd64 | ✅ 2 lần, đa kiến trúc |
| Chạy smoke test | ✅ | ✅ |
| Push lên GHCR | ❌ | ✅ |
| Pull image | ❌ | ❌ |
| Deploy lên máy | ❌ | ❌ |

Hai việc cuối là phần của **Bài 2 — Jenkins** (`huong-dan-jenkins.md`).

### Ba điều rút ra

1. **Tách workflow theo giai đoạn của code.** PR cần phản hồi nhanh và an toàn
   (không push gì). Code đã merge mới cần tạo image thật. Gộp vào một file phải
   dùng `if:` ở từng bước — chạy được nhưng khó đọc hơn.

2. **Chỉ xin quyền thật sự cần.** `ci.yml` không push nên chỉ xin `contents: read`.
   Lỡ có lỗi trong workflow, nó cũng không thể đẩy gì lên registry.

3. **Build một lần vẫn tốt hơn.** `ci.yml` làm được nhờ `SMOKE_IMAGE`.
   `build-test-push.yml` đổi lấy sự đơn giản bằng việc build 2 lần — chấp nhận
   được, nhưng phải biết mình đang đánh đổi cái gì.
