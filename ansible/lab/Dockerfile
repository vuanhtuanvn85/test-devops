# ===================================================================
# "SERVER ẢO" để học Ansible — một container Ubuntu có SSH.
# ===================================================================
#
# Vì sao phải làm cái này?
#   Học Ansible cần ít nhất một máy ở XA để điều khiển qua SSH.
#   Thuê server cloud thì tốn tiền và mất thời gian đăng ký.
#   Container này giả làm server: có SSH, có systemd-less init, có sudo.
#
# Điểm khác server thật (chấp nhận được khi học):
#   - Không có systemd, nên ta chạy Docker theo cách thủ công ở Bài 3.
#   - Chạy privileged để Docker-trong-Docker hoạt động.
#
# Đây CỐ Ý là container "béo" (fat container) — ngược với nguyên tắc
# 1 container 1 tiến trình. Lý do: nó đóng vai MÁY, không phải DỊCH VỤ.

FROM ubuntu:22.04

# Tránh apt hỏi timezone giữa lúc build rồi treo vô hạn
ENV DEBIAN_FRONTEND=noninteractive

# openssh-server : để Ansible kết nối vào
# python3        : BẮT BUỘC — Ansible đẩy module Python lên máy đích rồi chạy
# sudo           : playbook cần "become: yes" để cài gói
# ca-certificates, curl, gnupg : Bài 3 cài Docker cần
RUN apt-get update && apt-get install -y \
        openssh-server \
        python3 \
        sudo \
        curl \
        ca-certificates \
        gnupg \
        iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Thư mục SSH daemon cần để chạy, ảnh gốc không có sẵn
RUN mkdir -p /var/run/sshd

# ===== Tạo user "deploy" để Ansible đăng nhập =====
# Không dùng root trực tiếp: server thật hầu như luôn tắt đăng nhập root.
# Tập đúng thói quen ngay từ khi học.
RUN useradd -m -s /bin/bash deploy \
    && echo 'deploy:deploy123' | chpasswd \
    && usermod -aG sudo deploy \
    && echo 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/deploy \
    && chmod 0440 /etc/sudoers.d/deploy

# ===== Nhận khóa SSH công khai =====
# Khóa được sinh bằng ./ansible/lab/setup-lab.sh rồi copy vào lúc build.
COPY authorized_keys /home/deploy/.ssh/authorized_keys
RUN chown -R deploy:deploy /home/deploy/.ssh \
    && chmod 700 /home/deploy/.ssh \
    && chmod 600 /home/deploy/.ssh/authorized_keys

# Tắt đăng nhập bằng mật khẩu -> chỉ vào được bằng khóa.
# Giống cấu hình server production chuẩn.
RUN sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

EXPOSE 22

# -D : chạy ở foreground (container cần tiến trình chính không thoát)
# -e : ghi log ra stderr để "docker logs" xem được
CMD ["/usr/sbin/sshd", "-D", "-e"]
