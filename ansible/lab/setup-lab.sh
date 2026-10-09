#!/usr/bin/env bash
# ===================================================================
# Dựng phòng lab Ansible: sinh khóa SSH rồi bật 2 server ảo.
# ===================================================================
#
#   ./setup-lab.sh          # dựng lab
#   ./setup-lab.sh clean    # xoá sạch lab (container + khóa)
#
# Vì sao cần script mà không gọi thẳng "docker compose up"?
#   Dockerfile COPY file authorized_keys vào image. File đó chưa tồn tại
#   ở lần chạy đầu -> build lỗi. Script sinh khóa trước rồi mới build.

set -euo pipefail
cd "$(dirname "$0")"

KEY="$HOME/.ssh/ansible_lab"

# ---------- Chế độ dọn dẹp ----------
if [[ "${1:-}" == "clean" ]]; then
  echo "=== Xoá container lab ==="
  docker compose down -v 2>/dev/null || true
  echo "=== Xoá khóa SSH của lab ==="
  rm -f "$KEY" "$KEY.pub" authorized_keys
  # Xoá dấu vân tay cũ, tránh lỗi "REMOTE HOST IDENTIFICATION HAS CHANGED"
  # khi dựng lại lab (container mới sinh host key mới).
  ssh-keygen -R "[localhost]:2201" >/dev/null 2>&1 || true
  ssh-keygen -R "[localhost]:2202" >/dev/null 2>&1 || true
  echo "Đã dọn sạch."
  exit 0
fi

# ---------- Bước 1: sinh cặp khóa SSH ----------
# Cặp khóa = 1 khóa riêng (giữ bí mật ở laptop) + 1 khóa công khai (đặt lên server).
# Ansible dùng khóa riêng để chứng minh mình là "deploy" mà không cần mật khẩu.
if [[ ! -f "$KEY" ]]; then
  echo "=== Sinh khóa SSH cho lab: $KEY ==="
  # -N "" : không đặt passphrase, để Ansible chạy tự động không bị hỏi
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "ansible-lab" >/dev/null
  echo "Đã tạo khóa mới."
else
  echo "=== Dùng lại khóa có sẵn: $KEY ==="
fi

# Dockerfile cần file này nằm cạnh nó để COPY vào image
cp "$KEY.pub" authorized_keys

# ---------- Bước 2: dọn dấu vân tay SSH cũ ----------
# Lab dựng lại sẽ có host key khác. SSH nghi bị tấn công và chặn kết nối.
# Xoá trước cho êm.
ssh-keygen -R "[localhost]:2201" >/dev/null 2>&1 || true
ssh-keygen -R "[localhost]:2202" >/dev/null 2>&1 || true

# ---------- Bước 3: dựng 2 server ----------
echo ""
echo "=== Dựng 2 server ảo (web1, web2) ==="
docker compose down -v 2>/dev/null || true
docker compose up -d --build

# ---------- Bước 4: chờ SSH sẵn sàng ----------
echo ""
echo "=== Chờ SSH mở cổng ==="
for port in 2201 2202; do
  for i in $(seq 1 30); do
    # -o StrictHostKeyChecking=no : lần đầu chưa biết host key, tự chấp nhận
    # -o BatchMode=yes            : không hỏi gì, thất bại thì thoát luôn
    # -o IdentitiesOnly=yes       : CHỈ dùng khóa sau -i, bỏ qua khóa khác
    # -o IdentityAgent=none       : không hỏi ssh-agent xin khóa
    #
    # Vì sao cần 2 dòng cuối? Nếu ssh-agent của bạn đang giữ nhiều khóa
    # (ssh-add -l để xem), ssh sẽ thử LẦN LƯỢT từng khóa trong agent TRƯỚC
    # khóa chỉ định bằng -i. Server có MaxAuthTries = 6 (mặc định), nên nó
    # ngắt kết nối với lỗi "Too many authentication failures" trước khi
    # khóa lab được đưa ra. Triệu chứng: script báo "cổng không phản hồi"
    # dù sshd chạy hoàn toàn bình thường.
    if ssh -i "$KEY" \
           -o IdentitiesOnly=yes \
           -o IdentityAgent=none \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile="$HOME/.ssh/known_hosts" \
           -o BatchMode=yes \
           -o ConnectTimeout=2 \
           -p "$port" deploy@localhost 'echo ok' >/dev/null 2>&1; then
      echo "  cổng $port sẵn sàng sau ${i}s"
      break
    fi
    if [[ $i -eq 30 ]]; then
      echo "  LỖI: cổng $port không phản hồi sau 30s"
      echo ""
      echo "  Thử xem lỗi cụ thể:"
      echo "    ssh -v -i $KEY -o IdentitiesOnly=yes -o IdentityAgent=none -p $port deploy@localhost"
      echo "  Xem log sshd:"
      echo "    docker logs ansible-web1"
      exit 1
    fi
    sleep 1
  done
done

echo ""
echo "======================================================"
echo " PHÒNG LAB ĐÃ SẴN SÀNG"
echo ""
echo " SSH vào server (để quản lý):"
echo "   web1 : ssh -i $KEY -o IdentitiesOnly=yes -p 2201 deploy@localhost"
echo "   web2 : ssh -i $KEY -o IdentitiesOnly=yes -p 2202 deploy@localhost"
echo ""
echo " Mở app bằng browser (sau khi deploy ở Bài 3):"
echo "   web1 : http://localhost:8001"
echo "   web2 : http://localhost:8002"
echo "   (chưa deploy thì báo 'connection reset' — cổng đã mở nhưng chưa có app)"
echo ""
echo " Bước tiếp theo — kiểm tra bằng Ansible:"
echo "   cd .."
echo "   ansible all -m ping"
echo "======================================================"
