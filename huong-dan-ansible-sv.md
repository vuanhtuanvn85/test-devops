# Thực hành Ansible — Hướng dẫn cho sinh viên

Mục tiêu buổi này: **sửa code → push → 2 server tự cập nhật, không downtime.**

Bạn sẽ dựng 2 "server" ảo, dùng Ansible điều khiển chúng, rồi nối vào Jenkins
để tự động hoá toàn bộ.

> Tài liệu này là **các bước làm**. Muốn hiểu sâu từng khái niệm và tra lỗi chi
> tiết, xem [huong-dan-ansible.md](huong-dan-ansible.md).

---

## 0. Chuẩn bị

Cần có: **Docker Desktop đang chạy**, `git`, và `ansible`.

```bash
# Kiểm tra
docker --version
ansible --version

# Chưa có ansible thì cài:
#   macOS:  brew install ansible
#   Ubuntu: sudo apt install ansible
```

Mở terminal ở thư mục gốc project (`dictionary-app-5`).

---

## Phần 1 — Dựng 2 server ảo

### Bước 1.1. Chạy script

```bash
cd ansible/lab
./setup-lab.sh
```

Script làm 4 việc: sinh khoá SSH → build image → bật 2 container → chờ SSH sẵn sàng.

**Kết quả mong đợi:**

```
======================================================
 PHÒNG LAB ĐÃ SẴN SÀNG

 SSH vào server (để quản lý):
   web1 : ssh -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -p 2201 deploy@localhost
   web2 : ssh -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -p 2202 deploy@localhost

 Mở app bằng browser (sau khi deploy ở Bài 3):
   web1 : http://localhost:8001
   web2 : http://localhost:8002
======================================================
```

### Bước 1.2. Hiểu 2 loại cổng

Đây là chỗ sinh viên hay nhầm nhất:

| Cổng | Dùng để | Mở bằng |
| --- | --- | --- |
| **2201 / 2202** | Ansible SSH vào quản lý | lệnh `ssh` |
| **8001 / 8002** | Xem app từ điển | **browser** |

> Mở `http://localhost:2201` sẽ **lỗi** (đó là cổng SSH, không phải web).
> Mẹo nhớ: `22xx` họ cổng 22 = SSH. `80xx` họ cổng 80 = HTTP.

### Bước 1.3. Thử SSH vào server

```bash
ssh -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -p 2201 deploy@localhost
# Vào được thì gõ: hostname    -> in ra "web1"
# Thoát: exit
```

> **`-o IdentitiesOnly=yes` để làm gì?** Buộc SSH chỉ dùng khoá sau `-i`.
> Nếu máy bạn có nhiều khoá trong `ssh-agent` (kiểm tra: `ssh-add -l`), SSH sẽ
> thử hết khoá đó trước, server chỉ cho 6 lần thử rồi ngắt với lỗi
> `Too many authentication failures`. Thiếu option này là lab "chết" dù cấu
> hình hoàn toàn đúng.

### Dọn lab khi học xong

```bash
cd ansible/lab && ./setup-lab.sh clean
```

---

## Phần 2 — Ansible nói chuyện với server

```bash
cd ansible        # mọi lệnh ansible phải chạy từ thư mục này
```

> Vì sao? Vì `ansible.cfg` nằm ở đây. Ansible tự đọc nó để biết inventory ở đâu.
> Chạy ở thư mục khác sẽ lỗi "không tìm thấy host".

### Bước 2.1. Ping

```bash
ansible all -m ping
```

```
web1 | SUCCESS => { "ping": "pong" }
web2 | SUCCESS => { "ping": "pong" }
```

`pong` = SSH vào được **và** chạy được Python trên máy đích (Ansible cần Python
để thực thi module).

### Bước 2.2. Xem Ansible biết gì về server

```bash
ansible-playbook playbooks/01-ping.yml
```

```
TASK [In thông tin hệ thống] ***************************************
ok: [web1] => {
    "msg": "web1 | OS: Ubuntu 22.04 | Kiến trúc: aarch64 | RAM: 7934 MB | Python: 3.10.12"
}
```

Những thông tin này gọi là **facts** — Ansible tự thu thập, playbook dùng để
quyết định (ví dụ: Ubuntu thì dùng `apt`, CentOS thì dùng `yum`).

### Bước 2.3. Thử lệnh bất kỳ trên cả 2 server

```bash
ansible all -m shell -a "hostname && uptime"
```

**Đây chính là giá trị của Ansible: một lệnh, nhiều máy.**

---

## Phần 3 — Cài Docker lên 2 server

```bash
ansible-playbook playbooks/02-install-docker.yml
```

Mất 2–3 phút. Kết quả:

```
PLAY RECAP ****************************************************
web1    : ok=16   changed=6   unreachable=0   failed=0
web2    : ok=16   changed=6   unreachable=0   failed=0
```

### Bước 3.1. Bài học quan trọng — chạy lại lần nữa

```bash
ansible-playbook playbooks/02-install-docker.yml
```

```
web1    : ok=15   changed=0   unreachable=0   failed=0
```

**`changed=0`** — không sửa gì cả, vì Docker đã được cài rồi.

Đây là **idempotent**: playbook mô tả *trạng thái mong muốn*, không phải *các
bước làm*. Chạy 1 lần hay 10 lần đều cho kết quả như nhau. Script bash thường
không có tính chất này (cài lại, ghi đè, hỏng cấu hình).

---

## Phần 4 — Deploy ứng dụng

### Bước 4.1. Lấy `image_tag`

Playbook deploy **bắt buộc** có `image_tag` — tên image đã có trên registry.

```bash
cd ..                               # về thư mục gốc project
git push                            # đẩy code lên GitHub
gh run list --limit 3               # chờ dòng đầu là "completed success"

IMG=ghcr.io/vuanhtuanvn85/test-devops/web:$(git rev-parse HEAD)
docker pull $IMG                    # pull được = tag đúng
```

> **Vì sao không build trên server?** Vì **server không build gì cả** — đó là
> nguyên tắc. Server chỉ kéo image đã được test rồi chạy. Build trên production
> là anti-pattern: mỗi server build ra image hơi khác nhau, và cái bạn test
> không chắc là cái bạn chạy.
>
> Chạy playbook mà **không** có `image_tag` sẽ lỗi
> `failed to read dockerfile: no such file or directory` — vì source code
> không hề được copy lên server.

### Bước 4.2. Deploy

```bash
cd ansible
ansible-playbook playbooks/03-deploy-app.yml -e image_tag=$IMG
```

Image private (GHCR mặc định private) thì thêm token:

```bash
ansible-playbook playbooks/03-deploy-app.yml \
  -e image_tag=$IMG \
  -e ghcr_user=<tên-github> -e ghcr_token=<PAT>
```

> Thấy `skipping:` ở task *"Đăng nhập registry GHCR"* nghĩa là chưa truyền
> token → bước pull sẽ lỗi `unauthorized`.
>
> **Mỗi server phải login riêng.** Việc laptop bạn đã `docker login` không giúp
> gì cho web1/web2 — chúng có `dockerd` riêng.

**Kết quả:**

```
TASK [Chờ ứng dụng trả lời /api/health] ****************
ok: [web1]
ok: [web2]

TASK [Báo cáo deploy thành công] ***********************
"=== web1 DEPLOY THÀNH CÔNG ==="
"Health    : {\"db\":\"connected\",\"words\":10}"
"Tra từ    : {\"word\":\"computer\",\"definition\":\"máy tính\"}"
```

Hai dòng cuối là bằng chứng quan trọng nhất: **app trả lời thật, database có
dữ liệu**. Container "đang chạy" không đủ — nó có thể đang crash liên tục.

### Bước 4.3. Mở browser

```
web1 → http://localhost:8001
web2 → http://localhost:8002
```

Tra vài từ: `computer`, `dog`, `juice`, `house`.

---

## Phần 5 — Xem log

### Bước 5.1. CÁI BẪY: hai tầng container

```bash
docker logs ansible-web1          # SAI nếu muốn xem log app
```

Sẽ ra toàn log SSH:

```
Accepted publickey for deploy from 192.168.65.1 port 53596 ssh2: ...
Received disconnect from ...: disconnected by user
```

**Không phải lỗi.** Container `ansible-web1` giả làm **MÁY**, tiến trình chính
của nó là `sshd`. App chạy trong container **lồng bên trong** máy đó:

```
Docker Desktop (laptop)
└── ansible-web1              ← "MÁY", log = sshd
    └── dockerd (bên trong)
        ├── dictionary-web-1  ← APP  ← cái cần xem
        └── dictionary-db-1   ← DB
```

Phải đi xuyên **2 tầng**:

```bash
#          tầng 1          tầng 2
docker exec ansible-web1   docker logs dictionary-web-1
```

> **Docker Desktop không thể thấy app.** Nó chỉ nói chuyện với `dockerd` của
> laptop; app nằm ở `dockerd` thứ hai. Muốn xem log **buộc phải dùng dòng lệnh**.
> Server thật cũng vậy — Docker Desktop không bao giờ thấy container trên production.

### Bước 5.2. Cách nên dùng — Ansible hỏi cả 2 server

```bash
cd ansible
ansible all -m shell -a "docker logs --tail 20 dictionary-web-1" -b
```

```
web1 | CHANGED | rc=0 >>
[2026-10-09T22:04:57.657Z] web1 GET /api/define/house 200 17ms
web2 | CHANGED | rc=0 >>
[2026-10-09T22:01:10.763Z] web2 GET /api/define/juice 200 2ms
```

Output ghi rõ máy nào — **so sánh được 2 server cạnh nhau**.

### Bước 5.3. Đọc access log

```
[2026-10-09T22:04:57.657Z] web1 GET /api/define/house 200 17ms
     │                      │    │   │                │   └─ thời gian xử lý
     │                      │    │   └─ đường dẫn     └─ HTTP status
     │                      │    └─ method
     │                      └─ server nào trả lời
     └─ thời điểm (UTC)
```

| Nhìn thấy | Nghĩa là |
| --- | --- |
| Không có dòng nào khi tra từ | Request **không tới được** app — sai cổng, hoặc container chết |
| `200` | Thành công |
| `304` | Thành công, browser dùng cache |
| `404` | App sống, nhưng từ đó không có trong database |
| `503` | App sống, **database hỏng** → xem log db |

### Bước 5.4. Chỉ xem các lần tra từ

```bash
ansible web1 -m shell -a "docker logs --tail 50 dictionary-web-1 | grep define" -b
```

Theo dõi realtime (mở cửa sổ riêng, tra trên browser sẽ thấy log chạy ngay):

```bash
docker exec ansible-web1 docker logs -f dictionary-web-1
```

### Bước 5.5. Xem log database

```bash
ansible all -m shell -a "docker logs --tail 20 dictionary-db-1" -b
```

---

## Phần 6 — Rolling update: nâng cấp không downtime

### Vấn đề

`03-deploy-app.yml` chạy **song song** trên mọi server. Cả web1 và web2 cùng
restart → có vài giây **không server nào phục vụ** → người dùng thấy lỗi 502.

### Giải pháp: `serial: 1`

```bash
ansible-playbook playbooks/04-rolling-update.yml -e image_tag=$IMG
```

Mở `playbooks/04-rolling-update.yml` xem dòng quan trọng nhất:

```yaml
serial: 1        # làm xong hoàn toàn server 1 mới sang server 2
```

**Kết quả:**

```
>>> Đang nâng cấp web1 — các server khác vẫn phục vụ
<<< web1 đã chạy ghcr.io/...:c83bc28 và khỏe mạnh
>>> Đang nâng cấp web2 — các server khác vẫn phục vụ
<<< web2 đã chạy ghcr.io/...:c83bc28 và khỏe mạnh
```

### Thấy nó xảy ra thật

Mở **2 tab browser** cạnh nhau rồi bấm F5 liên tục trong lúc playbook chạy:

```
Tab 1 → http://localhost:8001
Tab 2 → http://localhost:8002
```

Bạn sẽ thấy **web1 gián đoạn vài giây rồi hồi phục, trong khi web2 vẫn phục vụ
bình thường** — rồi mới tới lượt web2. Không bao giờ cả hai cùng chết.

### Thứ làm nên rolling update

```yaml
- name: Chờ server này khỏe lại trước khi sang server tiếp theo
  uri:
    url: "http://localhost:{{ web_port }}/api/health"
  retries: 30
  until: health.status == 200 and 'connected' in health.content
```

Task này **chặn** Ansible lại. Server chưa khoẻ thì không sang server sau.
Bỏ task này thì `serial: 1` mất hết ý nghĩa.

---

## Phần 7 — Tự động hoá bằng Jenkins

Mục tiêu: **`git push` → 2 server tự cập nhật**.

### Vì sao Jenkins mà không phải GitHub Actions?

Runner của GitHub ở trên cloud, **không SSH vào được** `localhost:2201` của
laptop bạn. Jenkins chạy trong container ngay trên máy, cùng mạng Docker với
web1/web2 → demo được trọn vòng không cần server thật.

### Bước 7.1. Dựng Jenkins

```bash
cd jenkins
docker compose up -d --build        # phải dựng lab TRƯỚC (Jenkins cần mạng của lab)
```

Mở http://localhost:8080

### Bước 7.2. Thêm 2 credential

Manage Jenkins → Credentials → Add:

| ID | Loại | Nội dung |
| --- | --- | --- |
| `ghcr-credentials` | Username with password | user GitHub + PAT (`write:packages` + `read:packages`) |
| `ansible-lab-key` | Secret file | file `~/.ssh/ansible_lab` |

> Tạo PAT tại https://github.com/settings/tokens → Generate new token (classic).
> GitHub **không cho xem lại** token sau khi tạo — lưu lại ngay.

### Bước 7.3. Tạo job

New Item → **Pipeline** → đặt tên → trong phần Pipeline:

- Definition: **Pipeline script from SCM**
- SCM: Git, URL repo của bạn
- Script Path: `Jenkinsfile`

Save → **Build Now**.

### Bước 7.4. Pipeline chạy gì

```
git push
   ↓
1. BUILD    → build image
2. TEST     → smoke test
3. PUSH     → đẩy lên GHCR
4. PULL     → kéo về kiểm chứng
5. DEPLOY   → deploy lên LAPTOP (cổng 3000)
6. Kiểm tra
7. DEPLOY ĐA SERVER (Ansible)  → web1, LẦN LƯỢT rồi web2
8. Kiểm tra web1 + web2
```

Stage 5 và stage 7 cố ý tồn tại cùng nhau để **so sánh**:

| | Stage 5 | Stage 7 |
| --- | --- | --- |
| Deploy lên | 1 máy (laptop) | N máy (web1, web2) |
| Bằng | `docker compose` | **Ansible** |
| Thêm server thứ 3 | phải viết thêm code | **thêm 1 dòng inventory** |

### Bước 7.5. Demo trọn vòng

```bash
# Sửa một thứ nhìn thấy được, ví dụ thêm từ vào db/init.sql
git add -A && git commit -m "them tu moi" && git push
```

Jenkins tự phát hiện commit mới (2 phút/lần) rồi chạy cả 8 stage.

**Đây là điểm mấu chốt của cả buổi:** thêm server thứ 3 chỉ cần thêm 1 dòng vào
`inventory/hosts-ci.ini`. **Pipeline không phải sửa gì cả.** Đó là khác biệt
giữa *script* và *công cụ quản lý cấu hình*.

---

## Phần 8 — Lỗi hay gặp

### `Too many authentication failures`

Script báo "cổng 2201 không phản hồi" nhưng `docker logs ansible-web1` lại nói
"Too many authentication failures".

**Nguyên nhân:** `ssh-agent` của bạn có nhiều khoá (`ssh-add -l`). SSH thử hết
chúng trước khoá `-i`, server chỉ cho 6 lần rồi ngắt.

```bash
ssh -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -o IdentityAgent=none -p 2201 deploy@localhost
```

### `unauthorized` khi server pull image

```
Head "https://ghcr.io/v2/...": unauthorized
```

Package private mà server chưa login. Truyền token:

```bash
-e ghcr_user=<user> -e ghcr_token=<PAT>
```

Hoặc đổi package thành public trên GitHub (Packages → Package settings →
Change visibility).

### Container `Up` mà app chết, `ansible ping` vẫn OK

| Kiểm tra | Kết quả |
| --- | --- |
| `docker ps` | `Up` ✅ |
| `ansible all -m ping` | `SUCCESS` ✅ |
| `curl localhost:8001` | không trả lời ❌ |

**Nguyên nhân:** `dockerd` trong server đã chết (`sshd` vẫn sống nên ping OK).

```bash
# Chẩn đoán
ansible all -m shell -a "pgrep -x dockerd || echo 'DOCKERD CHET'" -b

# Sửa
ansible-playbook playbooks/02-install-docker.yml
```

### `invalid protocol identifier "GET / HTTP/1.1"`

Bạn mở `http://localhost:2201` — đó là cổng **SSH**. Dùng `8001`/`8002`.

### `Syntax error in template: unexpected '.'`

```bash
ansible all -m shell -a "docker ps --format '{{.Names}}'" -b     # LỖI
```

`{{ }}` trùng cú pháp biến Jinja2 của Ansible. Bỏ `--format`:

```bash
ansible all -m shell -a "docker ps" -b
```

---

## Tóm tắt lệnh

```bash
# Dựng lab
cd ansible/lab && ./setup-lab.sh

# Kiểm tra kết nối
cd .. && ansible all -m ping

# Cài Docker
ansible-playbook playbooks/02-install-docker.yml

# Deploy
IMG=ghcr.io/<user>/test-devops/web:$(cd .. && git rev-parse HEAD)
ansible-playbook playbooks/03-deploy-app.yml -e image_tag=$IMG

# Rolling update
ansible-playbook playbooks/04-rolling-update.yml -e image_tag=$IMG

# Xem log
ansible all -m shell -a "docker logs --tail 20 dictionary-web-1" -b

# Mở app
#   web1 → http://localhost:8001
#   web2 → http://localhost:8002

# Dọn
cd lab && ./setup-lab.sh clean
```

---

## 5 khái niệm cần nắm

| Khái niệm | Ý nghĩa | Thấy ở |
| --- | --- | --- |
| **Inventory** | Khai báo server nào, đăng nhập thế nào | `inventory/hosts.ini` |
| **Idempotent** | Chạy lại không phá thứ đang đúng (`changed=0`) | Phần 3.1 |
| **Facts** | Thông tin Ansible tự thu thập về máy đích | Phần 2.2 |
| **Handler** | Chỉ restart khi cấu hình thật sự đổi | `03-deploy-app.yml` |
| **`serial`** | Deploy lần lượt → không downtime | Phần 6 |

> Chi tiết hơn: [huong-dan-ansible.md](huong-dan-ansible.md)
