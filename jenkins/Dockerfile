# Jenkins + Docker CLI + Docker Compose v2
#
# Image jenkins/jenkins gốc KHÔNG có lệnh docker. Pipeline của ta gọi
# docker/docker compose liên tục nên phải cài thêm vào.
#
# Lưu ý: ta chỉ cài docker CLI (phần lệnh), KHÔNG cài Docker daemon.
# Daemon vẫn là Docker Desktop trên laptop; container Jenkins điều khiển
# daemon đó qua /var/run/docker.sock được mount vào (xem docker-compose.yml).
# Kiểu này gọi là "Docker outside of Docker" (DooD).

FROM jenkins/jenkins:lts-jdk17

# Cài đặt cần quyền root; cuối file trả lại user jenkins
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce-cli \
      docker-buildx-plugin \
      docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# ===== Ansible + SSH client (thêm ở buổi 7) =====
# Stage "DEPLOY ĐA SERVER" trong Jenkinsfile gọi ansible-playbook để đưa
# image lên web1/web2. Image jenkins gốc không có ansible lẫn ssh client.
#
# Vì sao ansible-core mà không phải gói "ansible" đầy đủ?
#   ansible-core ~20MB, chỉ gồm engine + module builtin — đủ cho playbook
#   của ta (file, copy, template, command, uri, assert đều là builtin).
#   Gói "ansible" đầy đủ ~500MB vì kèm hàng trăm collection không dùng tới.
#
# --break-system-packages: Debian 12 bảo vệ Python hệ thống, không cho pip
# ghi vào site-packages. Trong container thì không cần lớp bảo vệ đó —
# container này sinh ra chỉ để chạy Jenkins, không có app Python nào khác
# để mà phá vỡ.
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-pip \
      openssh-client \
 && pip3 install --no-cache-dir --break-system-packages ansible-core \
 && rm -rf /var/lib/apt/lists/* \
 && ansible --version

# Cài sẵn các plugin cần dùng, khỏi phải bấm chọn trong giao diện
RUN jenkins-plugin-cli --plugins \
      workflow-aggregator \
      git \
      credentials-binding \
      timestamper \
      ws-cleanup

USER jenkins
