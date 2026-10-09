# roles/ — dành cho bài tập 6

Thư mục này đang rỗng có chủ đích.

Bài tập 6 trong [hướng dẫn](../../huong-dan-ansible.md) yêu cầu bạn tách
`playbooks/02-install-docker.yml` thành một role.

Cấu trúc role chuẩn:

```
roles/docker/
├── tasks/main.yml        Các task chính (bắt buộc)
├── handlers/main.yml     Handler
├── defaults/main.yml     Biến mặc định (ưu tiên thấp nhất)
├── vars/main.yml         Biến của role (ưu tiên cao hơn defaults)
├── templates/            File .j2 (dùng với module template)
├── files/                File copy nguyên (dùng với module copy)
├── meta/main.yml         Thông tin role + role phụ thuộc
└── tests/                Playbook thử role
```

Trong role, module `template` và `copy` tự tìm file trong `templates/` và
`files/` nên bạn chỉ cần ghi tên file, không cần đường dẫn dài.

Tạo nhanh bộ khung:

```bash
ansible-galaxy init roles/docker
```

Gọi role trong playbook:

```yaml
- hosts: webservers
  become: yes
  roles:
    - docker
```

Role giúp gì so với playbook đơn lẻ? Tái sử dụng được giữa nhiều project, chia
việc cho nhiều người, và tải về role người khác đã viết từ Ansible Galaxy.
