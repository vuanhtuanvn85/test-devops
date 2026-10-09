# BÀI 3 — Ansible: tự động hóa cấu hình và deploy lên server

> Mục tiêu: từ hai server Ubuntu trắng trơn, chạy một lệnh duy nhất để cài
> Docker và deploy ứng dụng từ điển lên cả hai, xác nhận app trả lời thật.
>
> Thời lượng: 4 tiết (180 phút). Bài 1–3 làm trên lớp, Bài 4–5 làm ở nhà.

## Mục lục

**Phần lý thuyết**

1. [Ansible lấp vào chỗ nào của quy trình?](#1-ansible-lấp-vào-chỗ-nào-của-quy-trình)
2. [Ansible khác gì shell script?](#2-ansible-khác-gì-shell-script)
3. [Kiến trúc bài thực hành](#3-kiến-trúc-bài-thực-hành)
4. [Chuẩn bị](#4-chuẩn-bị)

**Phần thực hành**

| Bài | Nội dung                              | Mục |
| ---- | -------------------------------------- | ---- |
| 1    | Inventory và ad-hoc command           | 5    |
| 2    | Playbook cài Docker, hiểu idempotent | 6    |
| 3    | Deploy ứng dụng từ điển           | 7    |
| 4    | Nối Ansible vào Jenkins              | 11   |
| 5    | Rolling update                         | 12   |

**Phần kiến thức bổ trợ**

8. [Biến và thứ tự ưu tiên](#8-biến-và-thứ-tự-ưu-tiên) — hai cái bẫy hay gặp
9. [Ansible Vault](#9-ansible-vault-mã-hóa-mật-khẩu) — mã hóa mật khẩu
10. [Playbook tổng và tag](#10-playbook-tổng-và-tag)
11. [Lỗi thường gặp](#13-lỗi-thường-gặp) — mở khi bị kẹt
12. [Tổng kết](#14-tổng-kết-8-khái-niệm-đã-học)
13. [Bài tập](#15-bài-tập)

---

## 1. Ansible lấp vào chỗ nào của quy trình?

Hai bài trước đã dựng được:

| Bước | Công cụ                | Làm gì                                     |
| ------ | ------------------------ | -------------------------------------------- |
| BUILD  | Docker                   | Đóng gói app thành image                 |
| TEST   | smoke-test.sh            | Kiểm tra 8 điểm trên API                 |
| PUSH   | GitHub Actions / Jenkins | Đẩy image lên GHCR                        |
| PULL   | Jenkins                  | Kéo image từ registry về                  |
| DEPLOY | Jenkins + docker.sock    | Chạy container**trên chính laptop** |

Vấn đề nằm ở dòng cuối. Jenkins deploy qua `/var/run/docker.sock`, nên nó chỉ
điều khiển được Docker của laptop. Muốn đưa app lên một server Ubuntu thật, bạn
phải tự SSH vào rồi làm tay:

```bash
ssh deploy@server
sudo apt install docker-ce ...        # cài Docker
mkdir -p /opt/dictionary-app          # tạo thư mục
# copy docker-compose.yml lên (scp)
nano .env                             # gõ tay mật khẩu database
docker compose up -d
curl localhost:3000/api/health        # kiểm tra
```

Làm một server thì được. Làm ba server thì bắt đầu sai sót: server thứ hai bạn
gõ nhầm mật khẩu, server thứ ba bạn quên bước tạo thư mục.

**Ansible biến toàn bộ chuỗi trên thành một file văn bản chạy lại được.**

Ranh giới cần nhớ:

| Công cụ                | Trách nhiệm                                    |
| ------------------------ | ------------------------------------------------ |
| Jenkins / GitHub Actions | **TẠO RA** image đã được test        |
| Ansible                  | **ĐƯA** image đó lên server và chạy |

Hai việc khác nhau, đừng trộn lẫn.

---

## 2. Ansible khác gì shell script?

Đây là câu hỏi quan trọng nhất của bài. Nếu chỉ để chạy lệnh qua SSH thì viết
shell script cũng được, cần gì Ansible?

Hãy so sánh việc "thêm repository Docker":

**Shell script:**

```bash
echo "deb https://download.docker.com/linux/ubuntu jammy stable" \
  >> /etc/apt/sources.list.d/docker.list
```

Chạy lần 1: thêm một dòng. Chạy lần 2: thêm **dòng thứ hai giống hệt**. Chạy 5
lần: file có 5 dòng trùng nhau, apt bắt đầu cảnh báo.

**Ansible:**

```yaml
- name: Thêm repository Docker
  ansible.builtin.apt_repository:
    repo: "deb https://download.docker.com/linux/ubuntu jammy stable"
    state: present
```

Chạy bao nhiêu lần cũng chỉ có một dòng. Vì bạn không ra lệnh "hãy thêm vào",
bạn khai báo "trạng thái mong muốn là dòng này **phải có mặt**". Ansible tự
kiểm tra rồi quyết định làm gì.

Tính chất đó gọi là **idempotent** (bất biến khi lặp). Đây là khác biệt cốt lõi:

|                           | Shell script                        | Ansible                                     |
| ------------------------- | ----------------------------------- | ------------------------------------------- |
| Cách diễn đạt         | Ra lệnh từng bước (imperative)  | Khai báo trạng thái (declarative)        |
| Chạy lại lần 2         | Có thể gây hậu quả lạ         | Không làm gì, báo`changed=0`          |
| Nhiều server             | Tự viết vòng lặp + xử lý lỗi | Có sẵn, chạy song song                   |
| Biết cái gì đã đổi | Tự in ra                           | Báo cáo`changed` / `ok` / `skipped` |

Ansible cũng **không cần cài agent** lên server. Nó chỉ dùng SSH và Python,
hai thứ server Linux nào cũng có sẵn. Đây là lý do nó phổ biến hơn Puppet hay
Chef (các công cụ đó bắt cài daemon trên mọi máy).

---

## 3. Kiến trúc bài thực hành

Ta không thuê server cloud. Ta dùng hai container Ubuntu có SSH, coi chúng
là hai server thật.

```
   ┌──────────────────── LAPTOP (máy bạn) ─────────────────────┐
   │                                                            │
   │   ansible-playbook  ─────────────┐                         │
   │   (đọc inventory + playbook)     │                         │
   │                                  │ SSH cổng 2201 / 2202    │
   │                                  ▼                         │
   │   ┌─── container web1 ───┐   ┌─── container web2 ───┐      │
   │   │  Ubuntu 22.04        │   │  Ubuntu 22.04        │      │
   │   │  sshd + python3      │   │  sshd + python3      │      │
   │   │                      │   │                      │      │
   │   │  (Bài 3) Docker ────┐│   │  (Bài 3) Docker ────┐│      │
   │   │  (Bài 4) app ───────┤│   │  (Bài 4) app ───────┤│      │
   │   │    web + db         ││   │    web + db         ││      │
   │   └─────────────────────┘│   └─────────────────────┘│      │
   │      "server ảo" số 1        "server ảo" số 2              │
   └────────────────────────────────────────────────────────────┘
```

**Vì sao container lại chạy được Docker bên trong?** Vì `docker-compose.yml`
của lab đặt `privileged: true`. Server thật không cần dòng này. Đó là cái giá
của việc giả lập máy bằng container.

**Điểm khác server thật:** container không có systemd, nên playbook phải khởi
động Docker daemon thủ công. Playbook có ghi rõ đoạn nào là để lách và trên
server thật thì viết thế nào.

---

## 4. Chuẩn bị

### 4.1. Cài Ansible

Ansible chạy trên máy bạn, **không** cài gì lên server.

```bash
# macOS
brew install ansible

# Ubuntu / WSL
sudo apt update && sudo apt install -y ansible

# Cách nào cũng được (Python pip) — khuyến nghị nếu hai cách trên lỗi
python3 -m pip install --user ansible-core
```

Kiểm tra:

```bash
ansible --version
```

> **Windows:** Ansible không chạy native trên Windows. Dùng WSL2 (Ubuntu),
> hoặc chạy trong container. Đây là giới hạn của chính Ansible.

### 4.2. Dựng phòng lab

```bash
cd "dictionary-app-5/ansible/lab"
./setup-lab.sh
```

Script này làm 4 việc, theo đúng thứ tự bắt buộc:

1. Sinh cặp khóa SSH vào `~/.ssh/ansible_lab`
2. Copy khóa công khai thành `authorized_keys` (Dockerfile cần file này)
3. Build và bật hai container `web1`, `web2`
4. Chờ SSH mở cổng rồi báo sẵn sàng

> **Vì sao phải dùng script mà không gõ `docker compose up` trực tiếp?**
> Dockerfile có dòng `COPY authorized_keys ...`. File đó chưa tồn tại ở lần chạy
> đầu nên build sẽ lỗi. Script sinh khóa trước rồi mới build.

Kết quả mong đợi:

```
======================================================
 PHÒNG LAB ĐÃ SẴN SÀNG

   web1 : ssh -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -p 2201 deploy@localhost
   web2 : ssh -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -p 2202 deploy@localhost
```

> **`-o IdentitiesOnly=yes` để làm gì?** Nó buộc SSH **chỉ** dùng khóa sau `-i`.
> Nghe vô lý — đã chỉ định `-i` rồi mà? Nhưng không: `-i` với SSH chỉ là *gợi ý*,
> nó vẫn thử tất cả khóa trong `ssh-agent` trước. Xem mục
> [13](#too-many-authentication-failures) để hiểu vì sao điều đó làm lab chết.

### 4.2b. Hai cổng cho hai mục đích khác nhau

Mỗi "server" ảo mở **hai** cổng ra laptop:

| Cổng laptop | → trong container | Dùng để |
| --- | --- | --- |
| 2201 / 2202 | 22 (SSH) | Ansible **quản lý** server |
| 8001 / 8002 | 3000 (app) | **Mở browser** xem app |

Sau khi deploy xong, mở trong browser:

```
web1 -> http://localhost:8001
web2 -> http://localhost:8002
```

> **Dễ nhầm:** `http://localhost:3000` **KHÔNG phải** web1 hay web2 — đó là
> stack `dictionary-prod` mà Jenkins stage 5 deploy lên chính laptop. Khi demo,
> ba địa chỉ này là ba thứ hoàn toàn khác nhau:
>
> | Địa chỉ | Chạy ở đâu | Do ai deploy |
> | --- | --- | --- |
> | `localhost:3000` | laptop | Jenkins stage 5 (`docker compose`) |
> | `localhost:8001` | **web1** | Ansible stage 7 |
> | `localhost:8002` | **web2** | Ansible stage 7 |
>
> Cả ba cùng trả `{"db":"connected","words":10}` nên nhìn output không phân
> biệt được — phải nhìn cổng.

Vì sao dãy `800x` mà không phải `3000`/`3001`? Vì cổng 3000 trên laptop đã bị
stack của Jenkins chiếm. Hai thứ cùng xin một cổng thì container thứ hai không
khởi động được.

Nếu app chưa deploy, mở `localhost:8001` sẽ báo "connection reset" — cổng đã
forward nhưng chưa có gì nghe ở đầu bên kia. Deploy xong (mục 7) thì vào được.

Xoá lab khi học xong:

```bash
./setup-lab.sh clean
```

### 4.3. Hiểu về cặp khóa SSH

Ansible đăng nhập server **không dùng mật khẩu**. Nó dùng cặp khóa:

| Khóa                                  | Nằm ở đâu                         | Vai trò                                         |
| -------------------------------------- | ------------------------------------- | ------------------------------------------------ |
| Khóa riêng (`ansible_lab`)         | Laptop của bạn                      | Chứng minh danh tính.**Không đưa ai** |
| Khóa công khai (`ansible_lab.pub`) | Trên server, file`authorized_keys` | Server dùng để xác minh                      |

Cơ chế: server gửi một thử thách, laptop dùng khóa riêng ký, server dùng khóa
công khai kiểm tra chữ ký. Khóa riêng **không bao giờ** truyền qua mạng.

Vì sao dùng khóa thay mật khẩu? Mật khẩu có thể bị dò, và playbook tự động thì
không có ai ngồi gõ mật khẩu. Server thật luôn tắt `PasswordAuthentication` —
Dockerfile của lab cũng tắt để bạn quen môi trường thật.

---

## 5. BÀI 1 — Inventory: khai báo server

Mọi lệnh Ansible từ đây chạy trong thư mục `ansible/`:

```bash
cd "dictionary-app-5/ansible"
```

### 5.1. Đọc file inventory

Mở [ansible/inventory/hosts.ini](ansible/inventory/hosts.ini):

```ini
[webservers]
web1 ansible_host=localhost ansible_port=2201
web2 ansible_host=localhost ansible_port=2202

[webservers:vars]
ansible_user=deploy
ansible_ssh_private_key_file=~/.ssh/ansible_lab
ansible_python_interpreter=/usr/bin/python3
```

Giải thích từng phần:

- `[webservers]` — tên **nhóm**. Playbook nhắm vào nhóm, không nhắm vào từng máy.
- `web1` — **bí danh** bạn tự đặt, không phải tên miền thật.
- `ansible_host` — địa chỉ thật để kết nối.
- `[webservers:vars]` — biến áp dụng cho mọi máy trong nhóm, khỏi lặp lại.
- `ansible_python_interpreter` — Ansible **không chạy bằng bash**. Nó đẩy module
  Python lên máy đích rồi thực thi. Không có Python thì Ansible bó tay.

### 5.2. Kiểm tra Ansible hiểu file đúng không

```bash
ansible-inventory --graph
```

Kết quả:

```
@all:
  |--@ungrouped:
  |--@production:
  |  |--@webservers:
  |  |  |--web1
  |  |  |--web2
```

Xem chi tiết một máy — lệnh này rất hữu ích khi biến không như mong đợi:

```bash
ansible-inventory --host web1
```

### 5.3. Ad-hoc command: chạy một lệnh, không cần playbook

Ad-hoc dùng khi bạn chỉ muốn làm một việc nhanh, không đáng viết file.

```bash
# Kiểm tra kết nối tới TẤT CẢ server
ansible all -m ping
```

Kết quả đạt:

```
web1 | SUCCESS => {"changed": false, "ping": "pong"}
web2 | SUCCESS => {"changed": false, "ping": "pong"}
```

> Module `ping` **khác** lệnh `ping` mạng. Nó kiểm tra ba điều kiện cùng lúc:
> SSH vào được, Python chạy được, trả lời được. Cả ba đều cần cho mọi module khác.

Vài lệnh ad-hoc đáng thử:

```bash
# Xem dung lượng đĩa
ansible all -m shell -a "df -h /"

# Xem hệ điều hành (lấy từ facts)
ansible all -m setup -a "filter=ansible_distribution*"

# Chỉ chạy trên một máy
ansible web1 -m shell -a "hostname"

# Cài gói — cần quyền root nên thêm --become
ansible all -m apt -a "name=htop state=present" --become
```

Cấu trúc lệnh: `ansible <nhóm> -m <module> -a "<tham số>"`

### 5.4. Playbook đầu tiên

```bash
ansible-playbook playbooks/01-ping.yml
```

Mở [ansible/playbooks/01-ping.yml](ansible/playbooks/01-ping.yml) đọc song song.
Playbook này chỉ đọc, không sửa gì.

Kết quả:

```
PLAY RECAP *********************************************************
web1 : ok=5  changed=0  unreachable=0  failed=0
web2 : ok=5  changed=0  unreachable=0  failed=0
```

Đọc dòng RECAP — đây là thứ bạn sẽ đọc suốt buổi:

| Cột            | Nghĩa                                              |
| --------------- | --------------------------------------------------- |
| `ok`          | Task chạy xong, trạng thái đã đúng           |
| `changed`     | Task**đã thay đổi** gì đó trên server |
| `unreachable` | Không SSH được vào máy                        |
| `failed`      | Task lỗi                                           |
| `skipped`     | Bỏ qua vì`when:` không thỏa                   |

**`changed=0` ở playbook chỉ-đọc là đúng.** Chú ý trong file có dòng
`changed_when: false` ở task chạy `uptime`. Thiếu dòng đó Ansible sẽ báo
`changed` vì nó không biết lệnh shell làm gì — và báo cáo mất đi ý nghĩa.

---

## 6. BÀI 2 — Playbook cài Docker: hiểu idempotent

### 6.1. Chạy lần đầu

```bash
ansible-playbook playbooks/02-install-docker.yml
```

Mất khoảng 1–2 phút (tải Docker). Kết quả:

```
web1 : ok=14  changed=8  unreachable=0  failed=0
web2 : ok=14  changed=8  unreachable=0  failed=0
```

> Con số `changed` có thể khác chút tùy máy bạn (ví dụ apt cache còn mới thì
> task đầu báo `ok` thay vì `changed`). Điều cần đúng là `failed=0`.

### 6.2. Chạy lại lần thứ hai — đây là bài học chính

```bash
ansible-playbook playbooks/02-install-docker.yml
```

```
web1 : ok=13  changed=0  unreachable=0  failed=0  skipped=1
web2 : ok=13  changed=0  unreachable=0  failed=0  skipped=1
```

**`changed=0`** — đây là con số quan trọng. Ansible kiểm tra từng thứ, thấy đã
đúng hết, nên không làm gì. Chạy lần thứ 10 vẫn vậy.

Dòng `skipped=1` là task khởi động `dockerd` bị bỏ qua vì daemon đã chạy rồi,
đúng như thiết kế của `when:`.

So sánh với shell script: chạy 2 lần sẽ thêm repo 2 lần, cài lại gói, bật thêm
một tiến trình `dockerd` nữa.

Ý nghĩa thực tế của `changed=0`:

- Chạy playbook lên production **an toàn** — không có gì bị đụng nếu đã đúng.
- Bạn dùng playbook làm **công cụ kiểm tra**: `changed=0` nghĩa là server còn
  nguyên cấu hình chuẩn. Có `changed` nghĩa là ai đó đã sửa tay lên server.
- Cấu hình server trở thành **code kiểm tra được**, không phải trí nhớ.

### 6.3. Chế độ thử trước khi làm thật

```bash
ansible-playbook playbooks/02-install-docker.yml --check --diff
```

- `--check` — chạy giả, **không** thay đổi gì, chỉ báo cái gì *sẽ* đổi.
- `--diff` — hiện rõ từng dòng sẽ thêm/xoá trong file.

Đây là thói quen bắt buộc khi làm việc với server thật: xem trước rồi mới chạy.

> Lưu ý: một số task dùng `command`/`shell` không hỗ trợ `--check` đầy đủ, nên
> kết quả có thể không đủ 100%. Task dùng module chuẩn (`apt`, `file`,
> `template`) thì chính xác.

### 6.4. Xác nhận Docker đã cài

```bash
ansible all -m shell -a "docker --version && docker compose version"
```

### 6.5. Những kỹ thuật trong playbook cần chú ý

Mở [ansible/playbooks/02-install-docker.yml](ansible/playbooks/02-install-docker.yml)
và tìm các điểm sau:

**Biến facts giúp playbook chạy đa nền tảng**

```yaml
repo: >-
  deb [arch={{ 'amd64' if ansible_facts['architecture'] == 'x86_64' else 'arm64' }} ...]
  https://download.docker.com/linux/ubuntu
  {{ ansible_facts['distribution_release'] }} stable
```

Playbook tự điền kiến trúc CPU và tên bản Ubuntu. Cùng một file chạy đúng trên
Mac M-series (arm64), PC Intel (amd64), Ubuntu 22.04 (jammy) và 24.04 (noble).
Không sửa gì.

**`append: yes` — chi tiết nhỏ gây hậu quả lớn**

```yaml
- name: Thêm user deploy vào group docker
  ansible.builtin.user:
    name: deploy
    groups: docker
    append: yes     # ← THIẾU DÒNG NÀY LÀ MẤT QUYỀN sudo
```

Không có `append: yes`, Ansible hiểu là "user này **chỉ** thuộc group docker" và
**xoá** hết group khác, kể cả `sudo`. Kết quả: user mất quyền admin, playbook lần
sau chạy không được.

**`when:` tránh làm việc trùng**

```yaml
- name: Khởi động dockerd ở chế độ nền
  ansible.builtin.shell: nohup dockerd > /var/log/dockerd.log 2>&1 &
  when: docker_info.rc != 0
```

Chỉ bật khi daemon **chưa** chạy. Nhờ đó chạy lại playbook báo `skipping` chứ
không bật thêm tiến trình thứ hai.

**`retries` + `until` để chờ dịch vụ sẵn sàng**

```yaml
retries: 15
delay: 2
until: cho_docker.rc == 0
```

Thử lại 15 lần, cách nhau 2 giây. Docker daemon cần vài giây để nhận lệnh. Đây
là cách chờ đúng, thay vì `sleep 30` đoán bừa.

---

## 7. BÀI 3 — Deploy ứng dụng từ điển

Đây là bài chính. Playbook này làm đúng những việc bạn từng làm tay.

### 7.1. Deploy image từ registry

```bash
ansible-playbook playbooks/03-deploy-app.yml \
  -e image_tag=ghcr.io/vuanhtuanvn85/test-devops:$(git rev-parse --short=7 HEAD)
```

> **Vì sao BẮT BUỘC có `-e image_tag=...`?**
>
> Chạy trần không có `image_tag`:
>
> ```bash
> ansible-playbook playbooks/03-deploy-app.yml      # SẼ LỖI
> ```
>
> sẽ chết ở task `Dựng ứng dụng bằng docker compose`:
>
> ```
> failed to solve: failed to read dockerfile:
> open Dockerfile: no such file or directory
> ```
>
> Lý do: `docker-compose.yml` khai báo `web: build: .` — Docker cần
> `Dockerfile` + `backend/` + `frontend/` **trên server** để build. Playbook
> cố ý chỉ copy file cấu hình, **không copy source code** lên server.
>
> Đó không phải thiếu sót mà là nguyên tắc: **server không build gì cả.**
> Server chỉ kéo image đã được test rồi chạy. Build trên production là
> anti-pattern — mỗi server build ra image hơi khác nhau, cần toolchain trên
> server, deploy chậm, và cái bạn test không chắc là cái bạn chạy.
>
> **Làm sao biết `image_tag` của mình là gì?** Xem mục 7.1b ngay dưới.

Có `image_tag`, playbook tự thêm `-f docker-compose.prod.yml` và
`-f docker-compose.ansible.yml` nên compose **kéo image** thay vì build.
Đây chính là nguyên tắc "build một lần" của Bài 2.

Kết quả cuối:

```
TASK [Báo cáo deploy thành công] ***********************************
ok: [web1] => {
    "msg": [
        "=== web1 DEPLOY THÀNH CÔNG ===",
        "Image     : build từ source",
        "Health    : {\"db\":\"connected\",\"words\":10}",
        "Tra từ    : {\"word\":\"computer\",\"meaning\":\"máy tính\"}"
    ]
}
```

Hai dòng cuối là bằng chứng quan trọng nhất: **app trả lời thật, database có
đúng 10 từ, tra từ ra nghĩa tiếng Việt**. Container "đang chạy" không đủ — nó
có thể đang crash liên tục.

### 7.1b. Làm sao biết `image_tag` của mình?

`image_tag` **không phải thứ bạn tự nghĩ ra** — nó là tên image **đã thực sự
tồn tại trên registry**. Chưa ai push image thì chưa có `image_tag` nào cả.

Công thức luôn là:

```
<registry>/<chủ sở hữu>/<tên image>:<tag>
```

Trong project này `tag` = **git SHA của commit đã build**. Vì sao SHA mà không
phải `v1`, `v2`? Vì SHA trả lời được câu hỏi quan trọng nhất khi có sự cố:
*"bản đang chạy trên production là code nào?"* — `git show <sha>` là ra ngay.

**Bước 1 — chắc chắn code đã lên GitHub:**

```bash
git push
```

**Bước 2 — xem CI đã build xong chưa:**

```bash
gh run list --limit 3          # hoặc mở tab Actions trên GitHub
```

Phải thấy `completed success`. Đang `in_progress` thì chờ; `failure` thì chưa
có image, phải sửa lỗi build trước.

**Bước 3 — lấy SHA:**

```bash
git rev-parse HEAD          # SHA đầy đủ (GitHub Actions dùng)
git rev-parse --short=7 HEAD   # 7 ký tự (Jenkinsfile dùng)
```

> **CẢNH BÁO: hai CI trong repo này đặt tên image KHÁC NHAU.** Đây là chỗ rất
> dễ mất thời gian.
>
> | CI             | Tên image                                       | Tag                                  |
> | -------------- | ------------------------------------------------ | ------------------------------------ |
> | GitHub Actions | `ghcr.io/<user>/test-devops`**`/web`** | SHA**đầy đủ** (40 ký tự) |
> | Jenkins        | `ghcr.io/<user>/test-devops`                   | SHA**7 ký tự**               |
>
> Dùng CI nào thì lấy đúng tên của CI đó. Lấy lẫn sẽ bị
> `manifest unknown` hoặc `denied`.

**Bước 4 — kiểm chứng trước khi deploy.** Đừng đoán, hãy thử pull:

```bash
IMG=ghcr.io/vuanhtuanvn85/test-devops/web:$(git rev-parse HEAD)
docker pull $IMG
```

Pull được là `image_tag` đúng. Rồi mới deploy:

```bash
ansible-playbook playbooks/03-deploy-app.yml -e image_tag=$IMG
```

Dùng biến `$IMG` thay vì gõ tay cả chuỗi dài — vừa đỡ sai, vừa đảm bảo SHA
khớp đúng commit đang ở trong thư mục.

**Cách khác: xem trên web.** GitHub → trang repo → cột phải, mục **Packages** →
bấm vào package → tab **Versions** liệt kê mọi tag đã push.

**Nếu pull báo lỗi:**

| Lỗi                          | Nguyên nhân                                                                             |
| ----------------------------- | ----------------------------------------------------------------------------------------- |
| `manifest unknown`          | Tag không tồn tại — sai SHA, hoặc CI chưa push xong, hoặc lẫn tên giữa 2 CI     |
| `denied` / `unauthorized` | Package đang private →`docker login ghcr.io -u <user>` với PAT có `read:packages` |
| `name unknown`              | Sai tên image (thiếu/thừa`/web`)                                                     |

### 7.2. Kiểm tra bằng tay

```bash
# Xem container trên server
ansible all -m shell -a "docker ps"

# Muốn gọn hơn thì dùng --format table (KHÔNG dùng '{{.Names}}', xem ghi chú dưới)
ansible all -m shell -a "docker ps --format 'table {% raw %}{{.Names}}\t{{.Status}}{% endraw %}'"

# Gọi API từ trong server
ansible all -m uri -a "url=http://localhost:3000/api/health return_content=yes"

# Xem file .env Ansible đã sinh
ansible web1 -m shell -a "cat /opt/dictionary-app/.env" --become
```

> **Cái bẫy dấu ngoặc nhọn.** Docker dùng Go template (`{{.Names}}`), Ansible dùng
> Jinja2 (`{{ bien }}`). Cùng ký hiệu `{{ }}` nên Ansible tưởng `{{.Names}}` là
> biến của nó rồi báo lỗi:
>
> ```
> template error while templating string: unexpected '.'
> ```
>
> Cách xử lý: bọc trong `{% raw %}...{% endraw %}` để Ansible bỏ qua đoạn đó,
> hoặc đơn giản là dùng `docker ps` không có `--format`.

### 7.3. Kiểm tra idempotent

Chạy lại **đúng lệnh cũ, cùng `image_tag`**:

```bash
ansible-playbook playbooks/03-deploy-app.yml \
  -e image_tag=ghcr.io/vuanhtuanvn85/test-devops:$(git rev-parse --short=7 HEAD)
```

`changed=0`. App **không bị restart** vì không có gì thay đổi. Đây là lý do
playbook dùng handler thay vì restart vô điều kiện.

(Đổi `image_tag` khác thì `changed` > 0 — đúng như mong đợi, vì lúc đó thực sự
có thứ cần thay đổi.)

### 7.4. Ba file compose xếp lớp lên nhau

Khi deploy bằng Ansible, lệnh thật chạy trên server là:

```bash
docker compose -p dictionary \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  -f docker-compose.ansible.yml \
  up -d
```

File sau **đè** lên file trước. Mỗi file giải quyết một việc:

| File                           | Vai trò                                                                                                             |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `docker-compose.yml`         | Định nghĩa gốc:`web: build: .`, `db: postgres:16-alpine` + mount `init.sql`                                |
| `docker-compose.prod.yml`    | `web` dùng `image:` thay vì build. `db` **build** từ `./db` (vì Jenkins DooD không mount được) |
| `docker-compose.ansible.yml` | `db` quay lại dùng image chính thức + mount `init.sql`                                                       |

Nhìn qua thì file thứ ba có vẻ "hủy" file thứ hai. Thực ra chúng giải quyết
**hai môi trường khác nhau** của cùng một vấn đề:

- **Jenkins (DooD):** Jenkins ở trong container nhưng điều khiển Docker của
  HOST. Mount `./db/init.sql` thì daemon tìm đường dẫn đó **trên host** —
  workspace Jenkins không tồn tại ở đó → mount thư mục rỗng → Postgres bỏ qua
  `init.sql` → lỗi `relation "words" does not exist`. Nên phải **nhúng vào image**.
- **Ansible:** Ansible đã copy `init.sql` lên **đúng server đó**, và `dockerd`
  chạy ngay trên server đó. Đường dẫn tồn tại thật → mount được bình thường.
  Và server thì **không được build gì cả**.

> **Bài học thiết kế:** cùng một vấn đề, hai môi trường, hai cách giải. Tách
> thành file overlay riêng thay vì sửa file cũ — nhờ vậy bài Jenkins vẫn chạy
> đúng như đã dạy, không bị bài mới làm hỏng.

### 7.5. Kỹ thuật trong playbook deploy

Mở [ansible/playbooks/03-deploy-app.yml](ansible/playbooks/03-deploy-app.yml).

**`template` khác `copy`**

| Module       | Hành vi                               |
| ------------ | -------------------------------------- |
| `copy`     | Sao chép y nguyên từng byte         |
| `template` | Xử lý`{{ biến }}` trước khi ghi |

File [ansible/templates/env.j2](ansible/templates/env.j2) sinh ra `.env` trên
server. Cùng một template, đổi biến là ra config cho staging hoặc production.

**Quyền file bảo vệ mật khẩu**

```yaml
dest: "{{ app_dir }}/.env"
mode: '0600'        # chỉ chủ sở hữu đọc được
```

File này chứa mật khẩu database. `0644` là để mọi user trên server đọc được.

> **Chú ý:** phải viết `'0600'` trong dấu nháy. Không có nháy, YAML hiểu là số
> bát phân rồi chuyển thành `384` — sai quyền hoàn toàn.

**`loop` gộp task trùng lặp**

```yaml
- name: Copy các file compose và db lên server
  ansible.builtin.copy:
    src: "{{ playbook_dir }}/../../{{ item }}"
    dest: "{{ app_dir }}/{{ item }}"
  loop:
    - docker-compose.yml
    - docker-compose.prod.yml
    - db/Dockerfile
    - db/init.sql
```

Bốn file, một task. Thêm file thứ năm chỉ cần thêm một dòng.

**Handler: chỉ restart khi thật cần**

```yaml
    notify: Khoi dong lai ung dung      # ở task
...
handlers:
  - name: Khoi dong lai ung dung
    ansible.builtin.command: docker compose ... up -d --force-recreate
```

Ba task cùng `notify` handler này. Cả ba đổi file thì handler vẫn chỉ chạy
**một lần**, ở cuối playbook. Không file nào đổi thì handler **không chạy** —
app không bị gián đoạn vô cớ.

Đây là điểm shell script rất khó làm đúng.

**`no_log` chặn rò rỉ token**

```yaml
- name: Đăng nhập registry GHCR
  ansible.builtin.shell:
    cmd: echo "{{ ghcr_token }}" | docker login ...
  no_log: true        # ← không in nội dung task này
```

Thiếu dòng này, token hiện nguyên văn trong log Jenkins — ai xem log cũng lấy
được.

**Kiểm tra sau deploy mới là hoàn thành**

```yaml
- name: Chờ ứng dụng trả lời /api/health
  ansible.builtin.uri:
    url: "http://localhost:{{ web_port }}/api/health"
  retries: 30
  delay: 2
  until: health.status == 200 and 'connected' in health.content
```

Kiểm tra **nội dung**, không chỉ HTTP 200. App có thể trả 200 trong khi database
chưa sẵn sàng.

---

## 8. Biến và thứ tự ưu tiên

Ansible có hơn 20 mức ưu tiên biến. Ba mức bạn gặp hằng ngày:

| Mức | Nơi khai báo                               | Ưu tiên           |
| ---- | -------------------------------------------- | ------------------- |
| 1    | `inventory/group_vars/webservers/vars.yml` | Thấp               |
| 2    | `vars:` trong playbook                     | Ghi đè mức 1     |
| 3    | `-e` trên dòng lệnh                     | **Cao nhất** |

Thử nghiệm:

```bash
# Dùng cổng 3000 từ group_vars
ansible-playbook playbooks/03-deploy-app.yml -e image_tag=$IMG

# Ghi đè thành 8080 — không sửa file nào
ansible-playbook playbooks/03-deploy-app.yml -e image_tag=$IMG -e web_port=8080
```

(Đặt sẵn `IMG=ghcr.io/<user>/test-devops:<sha>` cho gọn. `image_tag` là bắt
buộc — xem mục 7.1.)

### 8.1. Hai cái bẫy về biến

**Bẫy 1: vị trí thư mục `group_vars`**

Ansible tìm `group_vars/` ở **cạnh file inventory**, không phải ở thư mục gốc.
Inventory của ta là `inventory/hosts.ini`, nên biến phải nằm ở:

```
ansible/inventory/group_vars/webservers/vars.yml     ✅ đúng
ansible/group_vars/webservers/vars.yml               ❌ Ansible không thấy
```

Đặt sai chỗ, playbook lỗi `AnsibleUndefinedVariable: 'postgres_user' is undefined`
và bạn sẽ mất rất nhiều thời gian tìm nguyên nhân. Kiểm tra bằng:

```bash
ansible-inventory --host web1
```

Biến nào không xuất hiện trong kết quả là Ansible không nạp được.

**Bẫy 2: biến tự tham chiếu**

Đừng bao giờ viết:

```yaml
vars:
  web_port: "{{ web_port | default(3000) }}"          # SAI
  web_port: "{{ web_port | default(3000, true) }}"    # VẪN SAI
```

Biến trỏ vào chính nó. Ansible báo `recursive loop detected` rồi in ra hàng trăm
dòng lỗi giống nhau, rất khó đọc. Thêm tham số `true` cũng không cứu được.

Cách đúng: để `group_vars` giữ giá trị, playbook **không nhắc lại** biến đó. Vẫn
đổi được lúc chạy bằng `-e` vì mức 3 cao hơn mức 1.

Trường hợp `default()` dùng được là khi **tên biến trong và ngoài khác nhau**:

```yaml
postgres_password: "{{ vault_postgres_password | default('dictpass') }}"
```

---

## 9. Ansible Vault: mã hóa mật khẩu

Hiện `.env` trên server chứa `POSTGRES_PASSWORD=dictpass`. Mật khẩu đang nằm
trong code, ai clone repo cũng đọc được. Vault giải quyết việc này.

### 9.1. Tạo file bí mật

```bash
cd "dictionary-app-5/ansible"

# Copy từ file mẫu
cp inventory/group_vars/webservers/vault.yml.example \
   inventory/group_vars/webservers/vault.yml

# Sửa giá trị thật
nano inventory/group_vars/webservers/vault.yml
```

Nội dung:

```yaml
vault_postgres_password: MatKhauManh_2026!xyz
vault_ghcr_token: ghp_token_that_cua_ban
```

### 9.2. Mã hóa

```bash
ansible-vault encrypt inventory/group_vars/webservers/vault.yml
```

Ansible hỏi mật khẩu vault — **đặt và nhớ nó**. Mất mật khẩu này là mất luôn
nội dung file, không có cách khôi phục.

Xem file sau khi mã hóa:

```bash
cat inventory/group_vars/webservers/vault.yml
```

```
$ANSIBLE_VAULT;1.1;AES256
33623764626533613666383861373463663864653966...
```

Nội dung thành chuỗi rối. **File này commit lên git được** — người khác clone về
cũng không đọc được.

### 9.3. Chạy playbook với vault

```bash
ansible-playbook playbooks/03-deploy-app.yml \
  -e image_tag=$IMG --ask-vault-pass
```

Thiếu `--ask-vault-pass`, Ansible báo lỗi "Attempting to decrypt but no vault
secrets found".

### 9.4. Các lệnh vault khác

```bash
# Xem nội dung mà không giải mã ra đĩa
ansible-vault view inventory/group_vars/webservers/vault.yml

# Sửa trực tiếp (tự mã hóa lại khi lưu)
ansible-vault edit inventory/group_vars/webservers/vault.yml

# Đổi mật khẩu vault
ansible-vault rekey inventory/group_vars/webservers/vault.yml
```

### 9.5. Quy ước đặt tên `vault_`

Mã hóa xong bạn không đọc được tên biến nữa. Nên quy ước:

- Biến trong vault đặt tên `vault_xxx`
- Playbook gán sang tên thường: `postgres_password: "{{ vault_postgres_password }}"`

Nhìn playbook là biết biến nào đến từ vault.

### 9.6. Vì sao tách hai file `vars.yml` và `vault.yml`?

| File          | Nội dung                       | Mã hóa |
| ------------- | ------------------------------- | -------- |
| `vars.yml`  | Cổng, đường dẫn, tên user | Không   |
| `vault.yml` | Mật khẩu, token               | Có      |

Nếu nhét tất cả vào vault thì mỗi lần đổi số cổng, `git diff` chỉ hiện một khối
rối không đọc được. Review code thành vô nghĩa.

---

## 10. Playbook tổng và tag

Chạy toàn bộ quy trình từ server trắng đến app chạy:

```bash
ansible-playbook playbooks/site.yml
```

Dùng tag để chạy một phần:

```bash
# Chỉ cài Docker
ansible-playbook playbooks/site.yml --tags docker

# Chỉ deploy lại app (Docker đã có, nhanh hơn nhiều)
ansible-playbook playbooks/site.yml --tags deploy

# Xem có tag nào
ansible-playbook playbooks/site.yml --list-tags
```

Trong thực tế bạn cài Docker một lần, rồi deploy hàng chục lần. Tag giúp không
phải chạy lại phần đã xong.

---

## 11. BÀI 4 — Nối Ansible vào Jenkins: push commit → 2 server tự cập nhật

Đây là bài đóng vòng CI/CD. Mục tiêu cụ thể:

> Sửa code, `git push` → Jenkins tự build, test, push image → Ansible tự đưa
> image đó lên **cả web1 và web2**, lần lượt từng máy, không gián đoạn dịch vụ.

Không ai SSH vào server nữa. Muốn biết server cấu hình thế nào thì đọc playbook.

### 11.1. Vì sao Jenkins mà không phải GitHub Actions?

Câu hỏi đáng đặt ra, vì repo này có cả `.github/workflows/`.

|                   | GitHub Actions               | Jenkins (trong lab này)           |
| ----------------- | ---------------------------- | ---------------------------------- |
| Chạy ở đâu    | Cloud của GitHub            | Container trên laptop bạn        |
| Thấy web1/web2?  | **Không**             | **Có** (cùng mạng Docker) |
| Demo trọn vòng? | Cần VPS thật có IP public | Chạy được ngay trên máy      |

Runner của GitHub nằm ngoài internet, không SSH vào `localhost:2201` của laptop
bạn được. Jenkins chạy ngay trong máy nên nối được vào mạng của lab.

Đó là lý do bài này dùng Jenkins. Trên server thật thì cả hai đều làm được.

### 11.2. Toàn cảnh

```
git push
    ↓
Jenkins pollSCM phát hiện commit mới (2 phút/lần)
    ↓
BUILD image  →  TEST (smoke-test, 8 điểm)  →  PUSH lên GHCR
    ↓
Ansible 03-deploy-app      : đưa cấu hình + image lên 2 server
    ↓
Ansible 04-rolling-update  : web1 xong & KHỎE  →  rồi mới tới web2
    ↓
Kiểm tra: cả 2 server cùng chạy đúng image vừa build
```

Hai stage cuối là phần thêm ở buổi này (stage 7 và 8 trong
[Jenkinsfile](Jenkinsfile)). Stage 5 cũ — deploy lên chính laptop — **vẫn giữ**,
để so sánh được "deploy 1 máy" với "deploy N máy".

### 11.3. Nối Jenkins vào mạng của lab

Đây là bước dễ bỏ sót nhất, và khi sai thì lỗi rất khó đoán.

Mặc định mỗi compose project có mạng riêng. Jenkins ở mạng của nó, web1/web2 ở
mạng `ansible-labnet` — hai bên **không gọi được nhau bằng tên**.

Sửa [jenkins/docker-compose.yml](jenkins/docker-compose.yml):

```yaml
services:
  jenkins:
    networks:
      - default      # mạng riêng của Jenkins
      - labnet       # mạng của web1/web2

networks:
  labnet:
    external: true            # KHÔNG tự tạo, dùng mạng đã có
    name: ansible-labnet
```

`external: true` là chỗ hay sai. Thiếu nó, compose **tạo một mạng mới** tên
`jenkins_labnet` và `docker compose up` vẫn báo thành công — nhưng Jenkins vẫn
không thấy web1/web2.

Phải dựng lab TRƯỚC, nếu không sẽ lỗi:

```
network ansible-labnet declared as external, but could not be found
```

### 11.4. Inventory riêng cho Jenkins

Cùng hai server, nhưng **đường đi khác nhau tùy chỗ gọi**:

| Gọi từ          | Đường đi                 | Inventory           |
| ----------------- | ---------------------------- | ------------------- |
| Laptop            | cổng forward 2201/2202      | `localhost:2201`  |
| Container Jenkins | mạng labnet, cổng 22 thật | `ansible-web1:22` |

Jenkins **không dùng được** `localhost:2201`, vì `localhost` trong container
Jenkins là chính nó, không phải laptop.

Nên có file riêng [ansible/inventory/hosts-ci.ini](ansible/inventory/hosts-ci.ini):

```ini
[webservers]
web1 ansible_host=ansible-web1 ansible_port=22
web2 ansible_host=ansible-web2 ansible_port=22
```

`ansible-web1` là `container_name`. Docker có DNS nội bộ cho từng mạng nên trong
cùng mạng gọi được nhau bằng tên — khỏi cần biết IP (và IP đổi sau mỗi lần dựng
lại lab).

File này đặt **cùng thư mục** với `hosts.ini` để dùng chung `group_vars/`.
Tách thư mục riêng thì phải nhân bản `group_vars`, sửa một chỗ quên chỗ kia.

### 11.5. Cài Ansible vào container Jenkins

Sửa [jenkins/Dockerfile](jenkins/Dockerfile):

```dockerfile
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-pip openssh-client \
 && pip3 install --no-cache-dir --break-system-packages ansible-core \
 && rm -rf /var/lib/apt/lists/*
USER jenkins
```

Ba chi tiết đều có lý do:

- **`ansible-core`** (~20MB) chứ không phải gói `ansible` đầy đủ (~500MB).
  Playbook của ta chỉ dùng module builtin (`file`, `copy`, `template`,
  `command`, `uri`, `assert`) nên core là đủ.
- **`openssh-client`** — image Jenkins gốc **không có lệnh `ssh`**. Thiếu nó
  Ansible báo lỗi lạ: `Unable to execute ssh command line on a controller: [Errno 2] No such file or directory: b'ssh'`.
- **`--break-system-packages`** — Debian 12 chặn pip ghi vào Python hệ thống.
  Trong container thì không cần lớp bảo vệ đó.

Build lại:

```bash
cd jenkins && docker compose up -d --build
```

### 11.6. Thêm credential vào Jenkins

| Loại                  | ID                   | Nội dung                                     |
| ---------------------- | -------------------- | --------------------------------------------- |
| Secret file            | `ansible-lab-key`  | File`~/.ssh/ansible_lab`                    |
| Username with password | `ghcr-credentials` | user GitHub + PAT (đã có từ bài Jenkins) |

PAT cần quyền **`write:packages`** (để Jenkins push) và **`read:packages`**
(để web1/web2 pull). Thiếu `read:packages` thì build qua được stage PUSH nhưng
chết ở stage 7 với lỗi `unauthorized` — xem mục 13.

Credential `ghcr-credentials` được dùng ở **hai nơi**: Jenkins tự login để
push, và stage 7 truyền xuống web1/web2 để chúng login mà pull.

Manage Jenkins → Credentials → Add.

Vì sao khóa phải đi qua credential mà không đọc thẳng `~/.ssh/ansible_lab`?
Jenkins chạy **trong container**, home của nó là `/var/jenkins_home` — không
thấy `~/.ssh` của laptop.

Trong pipeline, nhớ `chmod 600` sau khi copy khóa ra:

```groovy
sh '''
  cp "$ANSIBLE_KEY" /tmp/ansible_lab_key
  chmod 600 /tmp/ansible_lab_key
'''
```

SSH **từ chối** dùng khóa mà người khác đọc được
(`UNPROTECTED PRIVATE KEY FILE`), và Jenkins không tự set quyền này.

### 11.7. Hai stage mới

Stage 7 gọi lần lượt hai playbook:

```groovy
// 03: tạo thư mục, .env, copy compose, dựng db + web
ansible-playbook -i inventory/hosts-ci.ini playbooks/03-deploy-app.yml \
  -e image_tag=${env.TAG_SHA} \
  -e ansible_ssh_private_key_file=/tmp/ansible_lab_key

// 04: rolling update — web1 khỏe rồi mới sang web2
ansible-playbook -i inventory/hosts-ci.ini playbooks/04-rolling-update.yml \
  -e image_tag=${env.TAG_SHA} \
  -e ansible_ssh_private_key_file=/tmp/ansible_lab_key
```

**Vì sao cần cả hai?** `04` chỉ `--force-recreate web` — nó giả định `db` và
`.env` đã tồn tại. Server mới tinh chưa có gì thì `04` dừng ở task `assert`
với thông báo chỉ rõ phải chạy `03` trước.

Thực tế các lần deploy sau chỉ cần `04`. Ở đây chạy cả hai để minh họa, và vì
`03` idempotent nên chạy lại vô hại.

Stage 8 không tin stage 7 báo thành công — nó tự gọi vào từng server:

```groovy
for srv in ansible-web1 ansible-web2; do
  docker exec $srv curl -sf http://localhost:3000/api/health
  docker exec $srv curl -sf http://localhost:3000/api/define/computer | grep "máy tính"
  # và xác nhận ĐÚNG image vừa build, không phải bản cũ còn sót
done
```

### 11.8. Chuẩn bị trước khi chạy

```bash
# 1. Dựng lab (phải làm trước, vì Jenkins cần mạng ansible-labnet)
cd ansible/lab && ./setup-lab.sh

# 2. Cài Docker lên 2 server
cd .. && ansible-playbook playbooks/02-install-docker.yml

# 3. Dựng lại Jenkins (có Ansible + nối mạng labnet)
cd ../jenkins && docker compose up -d --build

# 4. Thêm credential 'ansible-lab-key' trong giao diện Jenkins
```

Kiểm tra Jenkins thấy được 2 server:

```bash
docker exec jenkins sh -c \
  'cd /var/jenkins_home/workspace/<tên-job>/ansible && \
   ansible all -i inventory/hosts-ci.ini -m ping \
     -e ansible_ssh_private_key_file=/tmp/ansible_lab_key'
```

### 11.9. Demo trên lớp

```bash
# Sửa một thứ nhìn thấy được, ví dụ thêm từ vào db/init.sql
git add -A && git commit -m "them tu moi" && git push
```

Rồi mở Jenkins xem pipeline chạy.

**Cách trực quan nhất — mở 2 tab browser cạnh nhau:**

```
Tab 1 -> http://localhost:8001     (web1)
Tab 2 -> http://localhost:8002     (web2)
```

Bấm F5 liên tục cả hai trong lúc pipeline chạy tới stage 7. Sinh viên sẽ thấy
**web1 gián đoạn vài giây rồi hồi phục, trong khi web2 vẫn phục vụ bình
thường** — rồi mới tới lượt web2. Không bao giờ cả hai cùng chết.

Đó chính là ý nghĩa của rolling update: người dùng cuối (nếu có load balancer
phía trước) **không thấy downtime** dù hệ thống vừa nâng cấp toàn bộ.

**Xem bằng dòng lệnh** (bổ sung, để thấy image tag đổi):

```bash
# Cửa sổ 1
watch -n1 'docker exec ansible-web1 docker ps --format "{{.Image}} {{.Status}}"'
# Cửa sổ 2
watch -n1 'docker exec ansible-web2 docker ps --format "{{.Image}} {{.Status}}"'
```

Điểm cần chỉ cho sinh viên: **web1 đổi image trước, web2 vẫn chạy bản cũ và
vẫn phục vụ**. Chỉ khi web1 khỏe lại thì web2 mới bắt đầu đổi. Xem cột
`Status` — thời gian uptime của hai máy lệch nhau vài chục giây, đó chính là
bằng chứng của `serial: 1`.

Kiểm tra nhanh cả hai cùng chạy đúng bản mới:

```bash
for p in 8001 8002; do echo -n "$p: "; curl -s localhost:$p/api/health; echo; done
```

**Cửa sổ thứ 3 — xem log app của cả hai server** (chỉ cho sinh viên thấy app
khởi động lại lần lượt, không cùng lúc):

```bash
cd ansible
watch -n2 'ansible all -m shell -a "docker logs --tail 3 dictionary-web-1" -b'
```

Pipeline fail thì đây cũng là lệnh đầu tiên nên chạy — xem mục
[13b](#13b-xem-log-của-web1-và-web2).

Rollback cũng là một lệnh, cũng rolling:

```bash
cd ansible && ansible-playbook -i inventory/hosts-ci.ini \
  playbooks/04-rolling-update.yml -e image_tag=ghcr.io/user/app:<sha_cũ>
```

### 11.10. Điểm mấu chốt của cả bài

Thêm server thứ ba vào hệ thống:

```ini
# inventory/hosts-ci.ini — thêm 1 dòng
web3 ansible_host=ansible-web3 ansible_port=22
```

**Pipeline không phải sửa gì cả.** Đó là lý do tồn tại của Ansible: cùng một
mô tả trạng thái, áp lên bao nhiêu máy cũng được.

So sánh với stage 5 (`docker compose` gọi trực tiếp) — muốn thêm máy thứ hai
phải viết thêm code. Đó là khác biệt giữa *script* và *công cụ quản lý cấu hình*.

---

## 12. BÀI 5 — Rolling update: nâng cấp không chết dịch vụ

### 12.1. Vấn đề

Playbook `03-deploy-app.yml` chạy **song song** trên mọi server. Cả web1 và web2
cùng restart một lúc, có vài giây không server nào phục vụ. Người dùng thấy lỗi.

### 12.2. Giải pháp: `serial`

```bash
ansible-playbook playbooks/04-rolling-update.yml \
  -e image_tag=ghcr.io/vuanhtuanvn85/test-devops:$(git rev-parse --short=7 HEAD)
```

Mở [ansible/playbooks/04-rolling-update.yml](ansible/playbooks/04-rolling-update.yml).
Dòng quan trọng nhất:

```yaml
serial: 1              # làm xong hẳn web1 mới sang web2
any_errors_fatal: true # web1 lỗi thì dừng, không lan sang web2
```

Quan sát output: Ansible chia thành hai lượt. Lượt một chỉ có web1, lượt hai chỉ
có web2.

Các lựa chọn khác:

```yaml
serial: 2            # 2 server mỗi lượt
serial: "50%"        # nửa số server mỗi lượt
serial: [1, 2, 5]    # canary: lượt đầu 1 máy thử nghiệm, rồi 2, rồi 5
```

### 12.3. Điều làm rolling update hoạt động

```yaml
- name: Chờ server này khỏe lại trước khi sang server tiếp theo
  ansible.builtin.uri:
    url: "http://localhost:{{ web_port }}/api/health"
  retries: 30
  until: health.status == 200 and 'connected' in health.content
```

Task này **chặn** Ansible lại. Server chưa khỏe thì không sang server sau. Bỏ
task này thì `serial: 1` mất hết ý nghĩa — vẫn có thể cả hai server chết cùng lúc.

### 12.4. Thứ tự các bước cũng quan trọng

Playbook kéo image **trước** khi tắt container cũ:

```yaml
- name: Kéo image mới về trước      # ← pull trước
- name: Cập nhật IMAGE_TAG trong .env
- name: Thay container bằng image mới # ← recreate sau
```

Nếu pull sau, server sẽ chết suốt thời gian tải image (có thể vài phút).

Và chỉ recreate service `web`, **không** chạm vào `db`:

```yaml
cmd: docker compose ... up -d --force-recreate web
```

Restart database là chuyện lớn: mất kết nối đang mở, có nguy cơ mất dữ liệu.

---

## 13. Lỗi thường gặp

### `UNREACHABLE! Failed to connect to the host via ssh`

```bash
# Lab còn chạy không?
docker ps | grep ansible-web

# Thử SSH tay để thấy lỗi thật
ssh -v -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -p 2201 deploy@localhost
```

Nếu lab đã tắt: `cd ansible/lab && ./setup-lab.sh`

Nếu SSH tay vào được mà Ansible vẫn `UNREACHABLE`, xem mục
[Too many authentication failures](#too-many-authentication-failures) ngay dưới.

### `Too many authentication failures`

Cũng là lỗi làm `setup-lab.sh` báo **"cổng 2201 không phản hồi sau 30s"** và làm
Ansible báo `UNREACHABLE` — dù container chạy hoàn toàn bình thường.

**Cách nhận ra.** Thông báo của script nói sai nguyên nhân. Hãy đọc log của sshd:

```bash
docker logs ansible-web1 | tail -5
```

Nếu thấy các dòng này thì đúng bệnh:

```
maximum authentication attempts exceeded for deploy from ...
Disconnecting authenticating user deploy ...: Too many authentication failures
```

Lưu ý: sshd **có** nhận kết nối và **có** trả lời. Cổng không hề "không phản hồi".

**Nguyên nhân.** Đếm số khóa trong agent của bạn:

```bash
ssh-add -l
```

Nếu agent đang giữ nhiều khóa (máy dùng nhiều GitHub/GitLab/công ty rất dễ có
5–10 khóa), SSH sẽ **thử lần lượt từng khóa trong agent TRƯỚC** khóa bạn chỉ định
bằng `-i`. Server chỉ cho tối đa **6 lần thử** (`MaxAuthTries`, mặc định của
OpenSSH), nên nó ngắt kết nối trước khi khóa lab được đưa ra.

Khóa lab hoàn toàn đúng — nó chỉ **không bao giờ đến lượt**.

Đây là lý do lab chạy được trên máy này nhưng chết trên máy khác: không phụ thuộc
cấu hình lab, mà phụ thuộc **số khóa trong `ssh-agent` của từng máy**.

**Cách sửa.** Thêm hai option để SSH chỉ dùng đúng khóa được chỉ định:

```bash
ssh -i ~/.ssh/ansible_lab \
    -o IdentitiesOnly=yes \
    -o IdentityAgent=none \
    -p 2201 deploy@localhost
```

| Option                 | Tác dụng                                                |
| ---------------------- | --------------------------------------------------------- |
| `IdentitiesOnly=yes` | Chỉ dùng khóa khai báo sau`-i`, bỏ qua khóa khác |
| `IdentityAgent=none` | Không hỏi`ssh-agent` xin khóa                        |

Cả `setup-lab.sh` và `ansible.cfg` của project **đã có sẵn** hai option này
(trong `ssh_args`). Nếu bạn tự viết script hay tự chạy `ansible` ở project khác
thì phải thêm tay.

> **Bài học mang đi:** mỗi khi dùng `ssh -i`, hãy kèm `IdentitiesOnly=yes`.
> Nó biến `-i` từ *"gợi ý thử khóa này"* thành *"chỉ dùng khóa này"*.

### `Head "https://ghcr.io/v2/...": unauthorized` khi server pull image

```
fatal: [web1]: FAILED! => {"cmd": ["docker", "pull", "ghcr.io/..."],
"stderr": "Error response from daemon:
Head \"https://ghcr.io/v2/.../manifests/9751e3e\": unauthorized"}
```

**Điều gây bối rối nhất:** Jenkins vừa pull **thành công** image đó ở stage 4,
mà web1/web2 lại báo `unauthorized` với đúng image ấy.

**Nguyên nhân.** `docker login` của Jenkins nằm trong Docker của **laptop**.
web1/web2 có `dockerd` **riêng**, không biết gì về login đó.

Nói cách khác: **đăng nhập registry là việc của từng máy**. N máy cần N lần
login. Đây là điều rất dễ quên khi chuyển từ "deploy 1 máy" sang "deploy N máy".

**Cách sửa — truyền token xuống server.** Playbook đã có task sẵn:

```yaml
- name: Đăng nhập registry GHCR
  ansible.builtin.shell:
    cmd: echo "{{ ghcr_token }}" | docker login ghcr.io -u "{{ ghcr_user }}" --password-stdin
  when: ghcr_token is defined and ghcr_token | length > 0
  no_log: true
```

Thấy `skipping:` ở task này nghĩa là **chưa truyền `ghcr_token`** → task không
chạy → pull thất bại. Truyền vào:

```bash
ansible-playbook playbooks/03-deploy-app.yml \
  -e image_tag=$IMG \
  -e ghcr_user=<user> -e ghcr_token=<PAT>
```

Trong Jenkins thì dùng credential, và phải cẩn thận **3 lớp** để token không lộ:

```groovy
withEnv(["TAG_SHA=${env.TAG_SHA}"]) {
  sh '''
    ansible-playbook ... \
      -e ghcr_token="$GHCR_CREDS_PSW"
  '''
}
```

| Lớp                  | Tác dụng                                                                             |
| --------------------- | -------------------------------------------------------------------------------------- |
| `'...'` nháy đơn | Groovy KHÔNG nội suy token vào chuỗi → không hiện trong log Jenkins             |
| Biến môi trường   | Không viết giá trị lên dòng lệnh → không lộ trong`ps aux` của máy đích |
| `no_log: true`      | Ansible không in nội dung task ra output                                             |

Dùng `"..."` (nháy kép) là **sai nghiêm trọng**: Groovy thay `$GHCR_CREDS_PSW`
bằng giá trị thật trước khi chạy, token hiện nguyên văn trong console log mà
ai xem Jenkins cũng đọc được.

**Cách nhanh hơn (đánh đổi):** đổi package thành public trên GitHub
(Packages → package → Package settings → Change visibility). Không cần token,
nhưng image của bạn ai cũng tải được, và bỏ qua bài học "server phải có
credential riêng". Production thì gần như luôn dùng registry private.

### `failed to solve: mount source: "overlay" ... invalid argument`

Hoặc khi tạo container:

```
Error response from daemon: failed to mount /tmp/containerd-mountXXX:
mount source: "overlay", ... err: invalid argument
```

**Nguyên nhân.** web1/web2 là container privileged nằm TRONG Docker Desktop.
Chạy `dockerd` trong đó nghĩa là overlayfs lồng trên overlayfs — kernel từ chối.
Docker 29 mặc định dùng containerd snapshotter với overlayfs nên lỗi ngay khi
tạo container đầu tiên.

Thông báo lỗi chỉ nói về "mount" và "snapshot", **không hề nhắc storage driver**,
nên rất khó đoán.

**Cách sửa.** [02-install-docker.yml](ansible/playbooks/02-install-docker.yml)
đã ghi `/etc/docker/daemon.json` trước khi bật dockerd:

```json
{
  "storage-driver": "vfs",
  "features": { "containerd-snapshotter": false }
}
```

`vfs` không dùng overlay — nó COPY toàn bộ layer thay vì xếp lớp. Chậm và tốn
đĩa hơn, nhưng chạy được ở mọi nơi.

Kiểm tra:

```bash
docker exec ansible-web1 docker info | grep "Storage Driver"
# Storage Driver: vfs
```

Lưu ý quan trọng: **server thật KHÔNG cần dòng này** — chúng có overlay2 chạy
tốt. Đây là thỏa hiệp chỉ dành cho lab giả lập bằng container.

> **Bài học:** `vfs` đánh đổi tốc độ để lấy tính tương thích. Khi môi trường
> lồng nhau nhiều lớp, driver "thông minh" nhất thường là driver hỏng trước.

### `Unable to execute ssh command line on a controller: ... b'ssh'`

Ansible chạy trong container (Jenkins, CI runner) mà container đó không có
lệnh `ssh`. Image `jenkins/jenkins` gốc không cài sẵn.

```dockerfile
RUN apt-get install -y openssh-client
```

Thông báo lỗi nói "on a controller" — controller là **máy chạy Ansible**, không
phải máy đích. Dễ đọc nhầm thành lỗi của server.

### `network ansible-labnet declared as external, but could not be found`

Jenkins khai báo dùng mạng của lab nhưng lab chưa dựng.

```bash
cd ansible/lab && ./setup-lab.sh
cd ../../jenkins && docker compose up -d
```

Thứ tự bắt buộc: lab tạo mạng trước, Jenkins mới nối vào được.

### `REMOTE HOST IDENTIFICATION HAS CHANGED`

Lab dựng lại sinh host key mới, SSH nghi bị tấn công.

```bash
ssh-keygen -R "[localhost]:2201"
ssh-keygen -R "[localhost]:2202"
```

`setup-lab.sh` đã tự làm việc này, nhưng nếu bạn dựng bằng `docker compose`
trực tiếp thì phải chạy tay.

### `ERROR! Invalid callback for stdout specified: yaml`

`ansible.cfg` bật callback không có sẵn trong `ansible-core`.

```bash
# Xem callback máy bạn có
ansible-doc -t callback -l

# Cài collection nếu muốn dùng
ansible-galaxy collection install ansible.posix
```

Trong repo này hai dòng đó đã để dạng chú thích nên bạn không gặp lỗi.

### `AnsibleUndefinedVariable: 'postgres_user' is undefined`

`group_vars` đặt sai chỗ. Xem lại mục 8.1.

```bash
ansible-inventory --host web1    # biến nào thiếu thì thấy ngay
```

### `recursive loop detected in template string`

Biến tự tham chiếu. Xem lại mục 8.1, bẫy 2.

### `template error while templating string: unexpected '.'`

Lệnh của bạn chứa `{{.Something}}` của Docker (Go template), Ansible tưởng đó là
biến Jinja2 của nó.

```bash
# Bọc lại để Ansible bỏ qua
ansible all -m shell -a "docker ps --format 'table {% raw %}{{.Names}}{% endraw %}'"

# Hoặc đơn giản là bỏ --format
ansible all -m shell -a "docker ps"
```

### `sudo: a password is required`

User trên máy đích chưa có quyền sudo không mật khẩu. Lab đã cấu hình sẵn. Trên
server thật:

```bash
echo 'deploy ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/deploy
sudo chmod 0440 /etc/sudoers.d/deploy
```

### Playbook luôn báo `changed` dù không sửa gì

Hai nguyên nhân phổ biến:

1. Task dùng `command`/`shell` mà thiếu `changed_when`. Ansible không biết lệnh
   shell làm gì nên luôn coi là đã đổi.
2. Template chứa giá trị đổi theo thời gian, ví dụ
   `{{ ansible_date_time.iso8601 }}`. Nội dung file luôn khác bản cũ nên Ansible
   luôn ghi lại, handler luôn chạy, app bị restart vô cớ.

Nguyên tắc: nội dung template chỉ được phụ thuộc vào **biến**, không phụ thuộc
**thời điểm** chạy.

### App không trả lời `/api/health`

Xem log trước khi đoán — mục [13b](#13b-xem-log-của-web1-và-web2) hướng dẫn chi tiết.

```bash
# Log app trên CẢ HAI server, một lệnh
ansible all -m shell -a "docker logs --tail 50 dictionary-web-1" -b

# Kiểm tra database có dữ liệu chưa
ansible web1 -m shell -a \
  "docker exec dictionary-db-1 psql -U dictuser -d dictionary -c 'SELECT count(*) FROM words;'" -b
```

---

## 13b. Xem log của web1 và web2

Khi app không chạy đúng, log là chỗ đầu tiên phải xem — đừng đoán.

Có **ba tầng log**, hỏng ở tầng nào thì xem tầng đó:

| Tầng | Xem gì | Khi nào |
| --- | --- | --- |
| 1. App (`web`) | Node.js in ra gì | App trả 500, không kết nối được db |
| 2. Database (`db`) | Postgres khởi tạo, query lỗi | `relation "words" does not exist` |
| 3. `dockerd` trên server | Daemon không tạo được container | Container không lên, lỗi mount/overlay |

### 13b.1. Cách nhanh nhất — Ansible hỏi cả hai server một lượt

Đây là cách nên dùng, vì **so sánh được hai server cạnh nhau**:

```bash
cd ansible

# Log app
ansible all -m shell -a "docker logs --tail 30 dictionary-web-1" -b

# Log database
ansible all -m shell -a "docker logs --tail 30 dictionary-db-1" -b

# Chỉ một server
ansible web1 -m shell -a "docker logs --tail 30 dictionary-web-1" -b
```

Output ghi rõ `web1 | CHANGED` rồi `web2 | CHANGED`, nên biết dòng nào của máy nào:

```
web1 | CHANGED | rc=0 >>
Server đang chạy tại http://localhost:3000
web2 | CHANGED | rc=0 >>
Server đang chạy tại http://localhost:3000
```

Đây chính là giá trị của Ansible khi đi gỡ lỗi: **một lệnh, N máy**. Server thứ
ba thì vẫn đúng lệnh đó.

> **`-b` là viết tắt của `--become`** (chạy bằng sudo).
>
> Với các lệnh `docker` ở trên thì **bỏ `-b` vẫn chạy được**, vì
> `02-install-docker.yml` đã thêm user `deploy` vào group `docker`:
>
> ```bash
> ansible all -m shell -a "groups deploy"
> # deploy : deploy sudo docker
> ```
>
Trong lab này, **mọi lệnh xem log ở mục 13b đều chạy được mà không cần `-b`**
(`/var/log/dockerd.log` có quyền `644`, ai cũng đọc được).

Nhưng vẫn nên giữ `-b` thành thói quen, vì server production thường khắt khe
hơn: không cho user thường vào group `docker` (vào group đó gần như tương
đương quyền root), và log hệ thống hay bị siết còn `640`. Giữ `-b` thì lệnh
chạy được ở cả hai kiểu cấu hình — bỏ đi thì có máy chạy máy không.

> ### CÁI BẪY: `--format` làm Ansible chết
>
> Gõ lệnh này sẽ **lỗi**, không phải lỗi Docker:
>
> ```bash
> ansible all -m shell -a "docker ps --format '{{.Names}}'" -b
> ```
>
> ```
> Syntax error in template: unexpected '.'
> ```
>
> Vì `{{ }}` là cú pháp biến của Jinja2. Ansible thấy `{{.Names}}` thì tưởng
> là biến của nó và cố render trước khi gửi lệnh đi.
>
> Hai cách thoát:
>
> ```bash
> # Cách 1 (đơn giản nhất): bỏ --format
> ansible all -m shell -a "docker ps" -b
>
> # Cách 2: bọc {% raw %} để Ansible bỏ qua
> ansible all -m shell -a "docker ps --format 'table {% raw %}{{.Names}}\t{{.Status}}{% endraw %}'" -b
> ```

### 13b.2. Xem trực tiếp bằng docker exec (nhanh, gọn)

Vì web1/web2 là container trên laptop, vào thẳng được — không cần SSH:

```bash
# Log app
docker exec ansible-web1 docker logs --tail 50 dictionary-web-1
docker exec ansible-web2 docker logs --tail 50 dictionary-web-1

# Theo dõi realtime (Ctrl+C để thoát)
docker exec ansible-web1 docker logs -f dictionary-web-1

# Log database
docker exec ansible-web1 docker logs --tail 50 dictionary-db-1
```

Cách này **chỉ dùng được trong lab**. Server thật không có `docker exec` từ
ngoài vào — phải SSH hoặc dùng Ansible. Nên tập dùng cách 13b.1 cho đúng
thói quen.

### 13b.3. SSH vào server rồi xem như server thật

Giống hệt khi gỡ lỗi production:

```bash
ssh -i ~/.ssh/ansible_lab -o IdentitiesOnly=yes -p 2201 deploy@localhost

# Rồi bên trong:
sudo docker ps
sudo docker logs --tail 50 dictionary-web-1
sudo docker compose -p dictionary -f /opt/dictionary-app/docker-compose.yml logs web
```

### 13b.4. Log của dockerd — khi container không lên được

Hai tầng trên chỉ có log khi container **đã chạy**. Nếu container không tạo
được thì phải xem log của daemon:

```bash
ansible all -m shell -a "tail -50 /var/log/dockerd.log" -b
```

Đây là nơi tìm thấy lỗi `overlay ... invalid argument` ở mục 13 — lỗi mà
`docker logs` không bao giờ cho thấy, vì container chưa kịp sinh ra.

### 13b.5. Xem log từ Jenkins

Pipeline fail ở stage 7/8 thì log Ansible đã nằm trong console log của Jenkins.
Muốn lấy thêm log app:

```bash
# Từ laptop, sau khi build fail
docker exec jenkins sh -c 'cd /var/jenkins_home/workspace/tmp/ansible && \
  ansible all -i inventory/hosts-ci.ini -m shell \
    -a "docker logs --tail 50 dictionary-web-1" -b \
    -e ansible_ssh_private_key_file=/tmp/ansible_lab_key'
```

Lưu ý: `/tmp/ansible_lab_key` bị **xoá sau mỗi build** (khối `post { always }`
của stage 7), nên lệnh trên chỉ chạy được giữa lúc build đang diễn ra. Sau khi
build xong thì dùng cách 13b.1 từ laptop.

### 13b.6. Bảng tra nhanh

| Triệu chứng | Xem log nào |
| --- | --- |
| `localhost:8001` không mở được | `docker ps` trên web1 — container có chạy không |
| Mở được nhưng trả 500 | Log **app** |
| `relation "words" does not exist` | Log **db** — init.sql có chạy không |
| `{"db":"disconnected"}` | Log **db** trước, rồi log app |
| Container `Created` mà không `Up` | Log **dockerd** |
| Deploy xong mà vẫn bản cũ | `docker ps` xem cột IMAGE — tag có đổi không |

---

## 14. Tổng kết: 8 khái niệm đã học

| Khái niệm                 | Ý nghĩa                                                   | Xem ở                    |
| --------------------------- | ----------------------------------------------------------- | ------------------------- |
| **Inventory**         | Khai báo server và cách đăng nhập                     | `inventory/hosts.ini`   |
| **Idempotent**        | Chạy lại không phá thứ đang đúng                    | Mục 6.2                  |
| **Declarative**       | Mô tả trạng thái mong muốn, không mô tả bước làm | Mục 2                    |
| **Facts**             | Thông tin tự thu thập, giúp playbook đa nền tảng     | `02-install-docker.yml` |
| **Template (Jinja2)** | Một file sinh nhiều config khác nhau                     | `templates/env.j2`      |
| **Handler**           | Chỉ restart khi cấu hình thật sự đổi                 | `03-deploy-app.yml`     |
| **Vault**             | Mã hóa mật khẩu, commit git an toàn                    | Mục 9                    |
| **Serial**            | Rolling update, không chết dịch vụ                      | Mục 12                   |

Và một so sánh cuối:

|                              | Trước (làm tay)              | Sau (Ansible)             |
| ---------------------------- | ------------------------------- | ------------------------- |
| Deploy 1 server              | 10 phút, dễ sai               | 1 lệnh                   |
| Deploy 5 server              | 50 phút, chắc chắn sai       | 1 lệnh, cùng thời gian |
| Biết server cấu hình gì  | Hỏi người cài, hoặc đoán | Đọc playbook            |
| Dựng lại server đã chết | Mò theo trí nhớ              | Chạy lại playbook       |
| Mật khẩu                   | Trong đầu, hoặc trong chat   | Trong Vault               |

---

## 15. Bài tập

**Bài 1 — Cơ bản.** Thêm server `web3` vào inventory (cổng 2203, sửa
`lab/docker-compose.yml`), rồi deploy lên cả ba server bằng một lệnh.

**Bài 2 — Template.** Sửa `templates/env.j2` thêm biến `APP_ENV`. Tạo hai
inventory `staging.ini` (cổng 3001, `APP_ENV=staging`) và `production.ini` (cổng
3000, `APP_ENV=production`). Deploy hai môi trường bằng **cùng một playbook**,
chỉ khác cờ `-i`.

**Bài 3 — Handler.** Chạy `03-deploy-app.yml` hai lần, xác nhận lần hai
`changed=0` và handler không chạy. Sau đó sửa một giá trị trong
`inventory/group_vars/webservers/vars.yml`, chạy lại, và giải thích vì sao
handler chạy lần này.

**Bài 4 — Vault.** Mã hóa mật khẩu database bằng Vault, deploy lại, rồi
`ansible-vault view` để xác nhận. Kiểm tra `.env` trên server đã dùng mật khẩu mới.

**Bài 5 — Rolling update.** Chạy `04-rolling-update.yml` và trả lời: nếu bỏ task
"Chờ server này khỏe lại" thì `serial: 1` còn tác dụng gì không? Vì sao?

**Bài 6 — Nâng cao: Role.** Tách `02-install-docker.yml` thành role
`roles/docker/tasks/main.yml`. Đọc tài liệu về cấu trúc role
(`tasks/`, `handlers/`, `defaults/`, `templates/`) rồi giải thích role giúp gì so
với playbook đơn lẻ.

**Bài 7 — Nâng cao: Jenkins.** Thực hiện mục 11, nối Ansible vào Jenkins, và
chạy trọn pipeline từ một commit đến app chạy trên cả hai server.

---

## 16. Đọc thêm

- Tài liệu chính thức: https://docs.ansible.com
- Danh sách module: `ansible-doc -l`
- Chi tiết một module: `ansible-doc apt`
- Ansible Galaxy (role có sẵn): https://galaxy.ansible.com

Hai lệnh đáng nhớ nhất khi gỡ lỗi:

```bash
ansible-inventory --host web1        # biến nào đang có giá trị gì
ansible-playbook <file> --check --diff  # xem trước khi làm thật
```
