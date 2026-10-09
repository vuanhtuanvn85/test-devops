#!/bin/bash
# ===================================================================
# Tiến trình khởi động của "server ảo"
# ===================================================================
#
# VÌ SAO CẦN FILE NÀY?
#
# Container lab giả làm MÁY. Máy thật khởi động lại thì systemd tự bật
# lại Docker. Container không có systemd, nên trước đây sau mỗi lần
# Docker Desktop khởi động lại:
#
#   - container web1/web2 chạy lại (chỉ có sshd, vì đó là CMD)
#   - dockerd KHÔNG sống lại  -> app biến mất
#   - "docker exec ansible-web1 docker ps" báo:
#         Cannot connect to the Docker daemon at unix:///var/run/docker.sock
#
# Triệu chứng gây nhầm lẫn nhất: Ansible vẫn ping OK (sshd còn sống),
# cổng 8001/8002 vẫn mở, nhưng không có log và không truy cập được app.
#
# File này đóng vai systemd tối giản: bật lại dockerd nếu đã cài, rồi
# giao quyền cho sshd làm tiến trình chính.

set -e

# Chỉ bật khi Docker ĐÃ được cài (bởi playbook 02-install-docker.yml).
# Lần dựng lab đầu tiên chưa có docker -> bỏ qua, không báo lỗi.
# Nhờ vậy bài học "dùng Ansible để cài Docker" vẫn giữ nguyên ý nghĩa.
if command -v dockerd >/dev/null 2>&1; then
  if ! pgrep -x dockerd >/dev/null 2>&1; then
    # ===== XOÁ PIDFILE MỒ CÔI =====
    # Container bị kill thì dockerd không kịp dọn /var/run/docker.pid.
    # Lần sau nó thấy pidfile cũ và TỪ CHỐI khởi động:
    #   failed to start daemon, ensure docker is not running or delete
    #   /var/run/docker.pid: process with PID 8 is still running
    #
    # Trong khi PID đó đã chết từ lâu. Chỉ xoá khi chắc chắn không còn
    # tiến trình dockerd nào (đã kiểm bằng pgrep ở trên).
    if [ -f /var/run/docker.pid ]; then
      echo "[entrypoint] Xoá pidfile mồ côi (PID $(cat /var/run/docker.pid))" >&2
      rm -f /var/run/docker.pid
    fi

    # Ghi ra stderr (>&2) để "docker logs ansible-web1" thấy được.
    # sshd chạy với -e nên cũng log ra stderr; cùng một luồng thì thứ tự
    # hiển thị mới đúng.
    echo "[entrypoint] Bật lại dockerd..." >&2
    nohup dockerd >> /var/log/dockerd.log 2>&1 &

    # Chờ daemon nhận lệnh. Không chờ thì container có restart:unless-stopped
    # sẽ cố start lúc socket chưa sẵn sàng.
    for i in $(seq 1 30); do
      if docker info >/dev/null 2>&1; then
        echo "[entrypoint] dockerd sẵn sàng sau ${i}s" >&2
        break
      fi
      sleep 1
    done
  fi
fi

# exec: sshd THAY THẾ shell này thành PID 1.
# Nhờ đó sshd nhận trực tiếp tín hiệu stop của Docker -> container dừng
# gọn gàng, không bị chờ 10s rồi SIGKILL.
echo "[entrypoint] Khởi động sshd" >&2
exec /usr/sbin/sshd -D -e
