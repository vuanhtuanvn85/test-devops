# Ansible — thư mục thực hành

Hướng dẫn đầy đủ: [../huong-dan-ansible.md](../huong-dan-ansible.md)

## Bắt đầu nhanh

```bash
# 1. Dựng 2 server ảo (chạy từ thư mục lab)
cd lab && ./setup-lab.sh && cd ..

# 2. Kiểm tra kết nối
ansible all -m ping

# 3. Cài Docker + deploy app lên cả 2 server
ansible-playbook playbooks/site.yml

# 4. Xoá lab khi học xong
cd lab && ./setup-lab.sh clean
```

> Mọi lệnh `ansible` phải chạy **từ thư mục này** (`ansible/`), vì `ansible.cfg`
> ở đây khai báo đường dẫn inventory.

## Cấu trúc

```
ansible/
├── ansible.cfg                 Cấu hình chung (inventory mặc định, SSH)
├── inventory/
│   ├── hosts.ini               Danh sách server + cách đăng nhập
│   └── group_vars/webservers/
│       ├── vars.yml            Biến công khai (cổng, đường dẫn)
│       └── vault.yml.example   Mẫu file mật khẩu (xem mục 9 hướng dẫn)
├── lab/
│   ├── Dockerfile              "Server ảo" Ubuntu có SSH
│   ├── docker-compose.yml      Dựng web1 + web2
│   └── setup-lab.sh            Sinh khóa SSH rồi bật lab
├── playbooks/
│   ├── 01-ping.yml             Kiểm tra kết nối (không sửa gì)
│   ├── 02-install-docker.yml   Cài Docker — bài học idempotent
│   ├── 03-deploy-app.yml       Deploy app từ điển
│   ├── 04-rolling-update.yml   Nâng cấp không chết dịch vụ
│   └── site.yml                Gộp tất cả, hỗ trợ --tags
└── templates/
    └── env.j2                  Template sinh file .env trên server
```

## Lệnh hay dùng

```bash
# Xem biến của một máy — dùng khi biến không như mong đợi
ansible-inventory --host web1

# Xem trước khi làm thật
ansible-playbook playbooks/03-deploy-app.yml --check --diff

# Chỉ deploy lại app, bỏ qua cài Docker
ansible-playbook playbooks/site.yml --tags deploy

# Deploy image thật từ registry
ansible-playbook playbooks/03-deploy-app.yml \
  -e image_tag=ghcr.io/<user>/<repo>:<sha>
```

## Lưu ý

- Cả 15 module dùng trong các playbook đều có sẵn trong `ansible-core`,
  không cần cài collection nào thêm.
- `group_vars/` phải nằm **trong** `inventory/`, không phải ở gốc. Đặt sai chỗ
  thì playbook lỗi `undefined variable`.
- `host_key_checking = False` trong `ansible.cfg` chỉ dùng khi học. Server thật
  phải bật lại.
