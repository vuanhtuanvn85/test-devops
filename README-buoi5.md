# BÀI LAB BUỔI 5 — Từ Linux container đến Docker Compose

Ứng dụng thực hành: **web tra từ điển Anh–Việt** (React + Express).

Bài lab đi qua 4 phần, mỗi phần là một nấc trên cùng một ứng dụng:

| Phần | Nội dung | Từ điển lấy từ đâu |
|---|---|---|
| 1 | Làm quen container với Alpine Linux | — |
| 2 | Chạy backend + frontend bằng `npm` | file JS |
| 3 | Đóng gói thành image bằng `Dockerfile` | file JS |
| 4 | Chạy 2 dịch vụ bằng `docker compose` | PostgreSQL |

Mạch xuyên suốt: chạy trực tiếp trên máy → đóng gói 1 container → tách thành 2 dịch vụ có database riêng.

## Chuẩn bị

- **Docker Desktop** đang chạy (biểu tượng cá voi trên thanh menu)
- **Node.js 18+** (`node -v`) — chỉ cần cho Phần 2

Kiểm tra nhanh:

```bash
docker --version
node -v && npm -v
```

## Cấu trúc thư mục

```
backend/            # backend CHÍNH - đọc từ điển từ PostgreSQL   (Phần 4)
  server.js
  db.js
frontend/           # React, dùng chung cho mọi phần
lab/                # bản dành riêng cho bài lab
  backend/          #   backend đọc từ điển từ file JS       (Phần 2, 3)
    server.js
    dictionary.js
  Dockerfile        #   Dockerfile không cần database        (Phần 3)
Dockerfile          # Dockerfile CHÍNH                            (Phần 4)
docker-compose.yml  # định nghĩa 2 dịch vụ web + db               (Phần 4)
db/init.sql         # tạo bảng + nạp dữ liệu ban đầu              (Phần 4)
.env                # user/password/tên DB và các cổng            (Phần 4)
```

Thư mục `lab/` tách riêng để Phần 2–3 chạy được **không cần database**, còn code chính vẫn giữ nguyên bản hoàn chỉnh dùng Postgres.

Các phần dùng cổng khác nhau nên chạy song song được: **3001** (Phần 2), **3002** (Phần 3), **8080** (Phần 4).

---

# PHẦN 1 — Làm quen container với Alpine Linux

Mục tiêu: hiểu container là gì trước khi đóng gói ứng dụng vào đó.

## 1.1 Tải image

```bash
docker pull alpine
docker images
```

Alpine là bản Linux tối giản, chỉ khoảng **13 MB** (so với Ubuntu ~78 MB). Đó là lý do nó được chọn làm nền cho hầu hết image trong bài này.

## 1.2 Chạy container và vào shell

```bash
docker run -it --rm alpine sh
```

Dấu nhắc đổi thành `/ #` — bạn đang ở bên trong Alpine.

Giải thích các cờ:

| Cờ | Ý nghĩa |
|---|---|
| `-i` | giữ stdin mở (interactive) |
| `-t` | cấp terminal giả (tty) — cho dấu nhắc và màu |
| `--rm` | tự xoá container khi thoát |

Alpine **không có `bash`**, chỉ có `sh`. Gõ `bash` sẽ báo *not found*.

## 1.3 Thử các lệnh Linux cơ bản

```sh
cat /etc/os-release        # xác nhận đang ở Alpine
whoami                     # root
uname -a                   # thông tin kernel
pwd                        # thư mục hiện tại
ls -la /                   # cây thư mục gốc

mkdir /demo && cd /demo
echo "xin chao" > a.txt
cat a.txt
ls -l

ps aux                     # rất ít process - container chỉ chạy sh
df -h                      # dung lượng ổ đĩa
```

Cài thêm gói bằng `apk` (Alpine dùng `apk`, không phải `apt`):

```sh
apk update
apk add curl
curl -s https://example.com | head -3
```

Thoát: gõ `exit` hoặc bấm **Ctrl+D**.

## 1.4 Bài học quan trọng: container sống bao lâu?

Thử lệnh sau — **container sẽ tắt ngay lập tức**:

```bash
docker run -d --name test1 alpine
docker ps                  # không thấy đâu cả
docker ps -a               # Exited (0)
```

Container sống đúng bằng tuổi thọ **tiến trình chính** của nó. Lệnh mặc định của alpine là `/bin/sh`; khi không có stdin, `sh` đọc được EOF ngay và thoát → container dừng theo. `Exited (0)` nghĩa là thoát bình thường, không phải lỗi.

Sửa bằng cách thêm `-it`:

```bash
docker rm test1
docker run -dit --name test1 alpine
docker ps                  # Up - đã chạy nền được
docker exec -it test1 sh   # vào shell của container đang chạy
```

Hoặc giao cho nó một việc chạy dài:

```bash
docker run -d --name test2 alpine sleep infinity
```

Ghi nhớ: `docker ps` chỉ hiện container **đang chạy**. Khi container "biến mất", luôn dùng `docker ps -a` rồi `docker logs <tên>` để biết vì sao.

Điều này giải thích vì sao ở Phần 3 và 4 không cần `-it`: tiến trình chính là web server, tự chạy mãi.

## 1.5 Dọn dẹp

```bash
docker rm -f test1 test2
```

---

# PHẦN 2 — Chạy backend và frontend bằng npm

Mục tiêu: chạy ứng dụng trực tiếp trên máy, chưa dùng Docker, để thấy Docker giải quyết vấn đề gì.

Phần này dùng `lab/backend/` — bản đọc từ điển từ **file JS**, không cần database.

## 2.1 Chạy backend

Mở **terminal thứ nhất**:

```bash
cd lab/backend
npm install
PORT=3001 npm start
```

Thấy dòng `Server đang chạy tại http://localhost:3001` là được. **Giữ terminal này mở** — đóng lại là server tắt.

Mở **terminal thứ hai** để test:

```bash
curl http://localhost:3001/api/health
curl http://localhost:3001/api/words
curl http://localhost:3001/api/define/apple
```

Kết quả:

```json
{"source":"file js","words":10}
["apple","book","computer",...]
{"word":"apple","definition":"quả táo"}
```

Trường `"source":"file js"` cho biết dữ liệu đang lấy từ [lab/backend/dictionary.js](lab/backend/dictionary.js). Ghi nhớ chi tiết này để so sánh với Phần 4.

Thử từ không có trong từ điển:

```bash
curl -i http://localhost:3001/api/define/xyz     # HTTP 404
```

## 2.2 Chạy frontend

Mở **terminal thứ ba**:

```bash
cd frontend
npm install
npm run dev
```

Vite chạy ở **http://localhost:5173**. Mở trình duyệt vào địa chỉ này.

Giao diện có listbox chọn từ và hiển thị nghĩa. Frontend gọi `/api/...` và được Vite chuyển tiếp sang backend cổng 3000 theo cấu hình proxy trong [frontend/vite.config.js](frontend/vite.config.js).

**Lưu ý**: proxy trỏ sẵn tới cổng 3000, nhưng ở trên ta chạy backend ở 3001. Muốn frontend gọi được, chạy backend ở cổng mặc định thay vì đặt `PORT`:

```bash
cd lab/backend && npm start        # cổng 3000
```

## 2.3 Build frontend ra file tĩnh

```bash
cd frontend
npm run build
```

Kết quả nằm trong `frontend/dist/` — HTML/CSS/JS tĩnh. Đây chính là thứ sẽ được copy vào image ở Phần 3.

## 2.4 Nhận xét

Cách chạy này bộc lộ nhiều bất tiện:

- Cần **3 terminal** và phải giữ chúng mở
- Phải cài Node đúng phiên bản trên mọi máy
- Chạy `npm install` riêng cho từng thư mục
- Máy khác Node phiên bản khác → có thể lỗi ("máy tôi chạy được mà")

Phần 3 gói tất cả vào 1 image để giải quyết những điều này.

## 2.5 Dừng lại

Bấm **Ctrl+C** ở từng terminal đang chạy server.

---

# PHẦN 3 — Build image bằng Dockerfile

Mục tiêu: đóng gói toàn bộ ứng dụng thành **một image** chạy được ở mọi nơi. Từ điển vẫn lấy từ file JS như Phần 2.

## 3.1 Đọc Dockerfile

Xem [lab/Dockerfile](lab/Dockerfile). Đây là **multi-stage build** gồm 2 tầng:

```dockerfile
# Tầng 1: dùng Node để build React
FROM node:20-alpine AS frontend-build
...
RUN npm run build

# Tầng 2: image cuối cùng
FROM node:20-alpine
COPY lab/backend/ ./
COPY --from=frontend-build /app/frontend/dist ./public
CMD ["node", "server.js"]
```

Tầng 1 chỉ mượn Node để chạy Vite build, rồi bị **vứt bỏ**. Tầng 2 chỉ lấy đúng thư mục `dist` kết quả.

Lợi ích: image cuối không chứa Vite, React và các gói build (`node_modules` của frontend), chỉ có Node runtime + Express + file tĩnh đã build.

## 3.2 Build image

Chạy từ **thư mục gốc dự án** (không phải trong `lab/`):

```bash
docker build -f lab/Dockerfile -t dictionary-lab:v1 .
```

- `-f lab/Dockerfile` — chỉ định file Dockerfile
- `-t dictionary-lab:v1` — đặt tên và tag cho image
- `.` — build context, thư mục Docker được phép đọc file

Xem kết quả:

```bash
docker images dictionary-lab
```

Khoảng **203 MB**. So sánh: `alpine` trơn 13.6 MB, `postgres:16-alpine` 411 MB.

## 3.3 Chạy container

```bash
docker run -d --name dict-lab -p 3002:3000 dictionary-lab:v1
docker ps
```

`-p 3002:3000` ánh xạ cổng: **3002 trên máy bạn** → **3000 trong container**. Số 3000 là cổng Express lắng nghe, khai báo bằng `EXPOSE 3000` trong Dockerfile.

Không cần `-it` như Phần 1, vì tiến trình chính là web server chạy mãi.

## 3.4 Test

Mở trình duyệt: **http://localhost:3002**

```bash
curl http://localhost:3002/api/health          # {"source":"file js","words":10}
curl http://localhost:3002/api/words
curl http://localhost:3002/api/define/guitar   # {"word":"guitar","definition":"đàn guitar"}
```

Vào bên trong container xem (áp dụng lệnh Linux từ Phần 1):

```bash
docker exec -it dict-lab sh
```

```sh
ls /app              # server.js, dictionary.js, public/, node_modules/
ls /app/public       # index.html + assets - kết quả build của Vite
cat /etc/os-release  # Alpine, giống Phần 1
exit
```

Xem log:

```bash
docker logs dict-lab
```

## 3.5 Hạn chế của cách này

Thử thêm một từ mới vào từ điển:

```bash
docker exec -it dict-lab sh
# vi /app/dictionary.js   ← sửa được, nhưng...
exit

docker restart dict-lab
curl http://localhost:3002/api/health
```

Sửa file bên trong container **sẽ mất khi container bị xoá và tạo lại**. Muốn thay đổi vĩnh viễn phải sửa `dictionary.js` rồi **build lại image**.

Đây là vấn đề cốt lõi: **dữ liệu không nên nằm trong image**. Phần 4 chuyển từ điển sang database riêng.

## 3.6 Dọn dẹp

```bash
docker rm -f dict-lab
```

---

# PHẦN 4 — Docker Compose với PostgreSQL

Mục tiêu: tách thành **2 dịch vụ** — `web` và `db` — chạy cùng lúc bằng một lệnh. Từ điển chuyển vào PostgreSQL.

Phần này dùng [backend/](backend/server.js) chính (đọc từ database), không phải `lab/`.

| Dịch vụ | Nội dung | Cổng host → container |
|---|---|---|
| `web` | React + Express, build từ [Dockerfile](Dockerfile) | `WEB_PORT` → 3000 |
| `db` | PostgreSQL 16 | `DB_PORT` → 5432 |

Cổng phía host do `.env` quyết định. Các lệnh dưới viết theo cấu hình mặc định của dự án (web **8080**, db **55432**) — nếu đổi `.env` thì thay số cho khớp, kiểm tra bằng `docker compose ps`.

## 4.1 Chuẩn bị cấu hình

File `.env` **đã có sẵn**, dùng luôn không cần làm gì.

File này khai báo 5 biến: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `WEB_PORT`, `DB_PORT`. Xem cấu trúc ở [.env.example](.env.example); giá trị thật mở trực tiếp file `.env` để đọc.

Chỉ khi `.env` bị mất mới cần `cp .env.example .env` — sau đó phải sửa lại giá trị và thay số cổng ở các bước dưới cho khớp.

Xem giá trị nào đang thực sự nạp vào 2 dịch vụ:

```bash
docker compose config
```

## 4.2 Đọc docker-compose.yml

Ba điểm đáng chú ý trong [docker-compose.yml](docker-compose.yml):

**`build: .` ở service web** — không dùng image có sẵn mà tự build từ Dockerfile chính. Khác với `db` dùng `image: postgres:16-alpine` kéo từ Docker Hub.

**`DB_HOST: db`** — backend kết nối tới host tên `db`, không phải `localhost`. Compose tạo network nội bộ và phân giải tên service thành IP.

**`depends_on: condition: service_healthy`** — web chờ tới khi db **thực sự nhận được kết nối**, không chỉ chờ container khởi động. Thiếu điều kiện này, web chạy trước và crash vì DB chưa sẵn sàng.

## 4.3 Khởi động

```bash
docker compose up --build -d
```

Bỏ `-d` nếu muốn xem log trực tiếp. Log sẽ hiện đúng thứ tự:

```
Container dictionary-db  Started
Container dictionary-db  Waiting
Container dictionary-db  Healthy      ← healthcheck báo sẵn sàng
Container dictionary-web Starting     ← web mới bắt đầu
```

Đó chính là tác dụng của `service_healthy`.

## 4.4 Kiểm tra 2 container

```bash
docker compose ps
```

```
NAME             STATUS                    PORTS
dictionary-db    Up 11 seconds (healthy)   0.0.0.0:55432->5432/tcp
dictionary-web   Up 6 seconds              0.0.0.0:8080->3000/tcp
```

Cột `STATUS` của `dictionary-db` phải là **`Up (healthy)`**.

## 4.5 Truy cập web và kiểm tra kết nối database

Mở trình duyệt: **http://localhost:8080**

- Badge xanh **"Database: đã kết nối (10 từ)"** → web query được DB
- Badge đỏ "Database: mất kết nối" → xem `docker compose logs web`
- Chọn từ trong listbox, nghĩa hiện ra là dữ liệu **lấy từ PostgreSQL**

Kiểm tra bằng dòng lệnh:

```bash
curl http://localhost:8080/api/health
curl http://localhost:8080/api/words
curl http://localhost:8080/api/define/computer
```

```json
{"db":"connected","words":10}
```

So với Phần 2–3 trả `{"source":"file js",...}` — đây là bằng chứng dữ liệu đã chuyển sang database.

## 4.6 Xem dữ liệu trực tiếp trong database

Các lệnh `psql` dùng biến từ `.env`, nên nạp file đó vào shell một lần trước (chỉ có tác dụng trong terminal hiện tại):

```bash
set -a && . ./.env && set +a
```

Không nạp thì psql lấy user mặc định và báo `role "root" does not exist`.

```bash
docker compose exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM words;"
```

Vào phiên psql tương tác:

```bash
docker compose exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

```sql
\dt                          -- liệt kê bảng
SELECT count(*) FROM words;
\q                           -- thoát
```

Dữ liệu này đến từ [db/init.sql](db/init.sql) — PostgreSQL tự chạy file `.sql` đặt trong `/docker-entrypoint-initdb.d/` **lần đầu khi volume còn rỗng**.

## 4.7 Xem log

```bash
docker compose logs          # cả 2 dịch vụ
docker compose logs -f web   # theo dõi riêng web
docker compose logs db
```

## 4.8 Dừng và xoá container

```bash
docker compose down
```

Lệnh này xoá container và network, **nhưng giữ lại volume `pgdata`**.

```bash
docker compose ps -a         # trống - container đã xoá
docker volume ls | grep pgdata   # volume vẫn còn
```

## 4.9 Chứng minh dữ liệu vẫn còn (volume)

Con số 10 không chứng minh được gì, vì đó cũng là số từ `init.sql` tạo ra. Muốn thấy rõ, phải **thêm dữ liệu mới** rồi mới `down`:

```bash
# 0. Nạp .env nếu dùng terminal mới, và up lại nếu vừa down ở 4.8
set -a && . ./.env && set +a
docker compose up -d

# 1. Thêm 1 từ không có trong init.sql
docker compose exec db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "INSERT INTO words (word, definition) VALUES ('docker', 'công cụ đóng gói ứng dụng');"

curl http://localhost:8080/api/health          # -> "words":11

# 2. Xoá container
docker compose down

# 3. Dựng lại
docker compose up -d
curl http://localhost:8080/api/health          # -> vẫn "words":11
curl http://localhost:8080/api/define/docker   # -> vẫn tra được
```

Vẫn 11 từ: container đã bị xoá và tạo mới hoàn toàn, nhưng dữ liệu nằm trong volume `pgdata` nên không mất. Nếu `init.sql` chạy lại thì con số đã quay về 10.

Đây chính là điều Phần 3 không làm được — ở đó sửa dữ liệu xong `docker rm` là mất sạch.

## 4.10 Xoá sạch cả dữ liệu

```bash
docker compose down -v
```

Cờ `-v` xoá luôn volume. Lần `up` kế tiếp, PostgreSQL thấy volume rỗng nên chạy lại `db/init.sql`, dữ liệu về đúng 10 từ ban đầu:

```bash
docker compose up -d
curl http://localhost:8080/api/health          # -> "words":10 (đã reset)
curl -i http://localhost:8080/api/define/docker # -> HTTP 404, từ thêm tay đã mất
```

---

# Tổng kết

## Bốn nấc đã đi qua

| | Cách chạy | Ưu điểm | Hạn chế |
|---|---|---|---|
| P2 | `npm start` | sửa code thấy ngay | cần 3 terminal, phụ thuộc Node trên máy |
| P3 | 1 container | chạy được mọi nơi | dữ liệu nằm trong image, sửa phải build lại |
| P4 | 2 dịch vụ | dữ liệu tách riêng, bền vững | cấu hình phức tạp hơn |

## Ba khái niệm cốt lõi

**Service discovery** — [backend/db.js](backend/db.js) kết nối tới host tên `db`, không phải `localhost` hay IP. Compose tạo DNS nội bộ để container gọi nhau bằng tên service.

**Volume** — dữ liệu PostgreSQL nằm trong named volume `pgdata`, tách khỏi vòng đời container. Container bị xoá, dữ liệu vẫn còn. Đây là khác biệt lớn nhất giữa Phần 3 và Phần 4.

**Healthcheck + depends_on** — `depends_on` thường chỉ chờ container *khởi động*, trong khi PostgreSQL cần thêm vài giây mới nhận kết nối. `condition: service_healthy` khiến web chờ đúng thời điểm.

## Bảng lệnh tra cứu

| Việc | Lệnh |
|---|---|
| Tải image | `docker pull alpine` |
| Vào shell container mới | `docker run -it --rm alpine sh` |
| Chạy nền giữ shell sống | `docker run -dit --name x alpine` |
| Vào container đang chạy | `docker exec -it <tên> sh` |
| Xem container đang chạy | `docker ps` |
| Xem cả container đã tắt | `docker ps -a` |
| Build image | `docker build -t <tên>:<tag> .` |
| Chạy container ánh xạ cổng | `docker run -d -p 8080:3000 <image>` |
| Xoá container | `docker rm -f <tên>` |
| Khởi động cả stack | `docker compose up --build -d` |
| Xem trạng thái stack | `docker compose ps` |
| Xem log | `docker compose logs -f <service>` |
| Vào DB | `docker compose exec db psql -U <user> -d <db>` |
| Dừng, giữ dữ liệu | `docker compose down` |
| Dừng, xoá dữ liệu | `docker compose down -v` |

---

# Xử lý sự cố

**Cổng đã bị chiếm** (`port is already allocated`)
Đổi `WEB_PORT` / `DB_PORT` trong `.env` sang số khác, rồi `docker compose up -d`. Chỉ cổng phía host đổi; bên trong container vẫn luôn là 3000 và 5432. Tìm tiến trình chiếm cổng: `lsof -i :8080`.

**Sửa code nhưng container không đổi**
Image `web` tự build nên phải `docker compose up --build`. Chạy `up` trơn sẽ dùng lại image cũ đã cache.

**Sửa `init.sql` nhưng dữ liệu không đổi**
File này chỉ chạy khi volume rỗng. Cần `docker compose down -v` rồi `up` lại.

**Badge đỏ "mất kết nối"**
```bash
docker compose logs db      # DB đã healthy chưa?
docker compose logs web     # xem lỗi kết nối phía backend
```
Thường do `.env` bị sửa lệch giữa nhóm `POSTGRES_*` (tạo user) và nhóm `DB_*` (kết nối vào).

**`psql: role "root" does not exist`**
Chưa nạp `.env` vào shell. Chạy `set -a && . ./.env && set +a` trước (mục 4.6).

**Container vừa tạo đã tắt**
`docker ps -a` xem mã thoát, `docker logs <tên>` xem nguyên nhân. Nếu là container shell thì thiếu `-it` (mục 1.4).

**Muốn build lại hoàn toàn sạch**
```bash
docker compose build --no-cache
```

**Dọn sạch mọi thứ của bài lab**
```bash
docker compose down -v
docker rm -f dict-lab test1 test2 2>/dev/null
docker rmi dictionary-lab:v1
```
