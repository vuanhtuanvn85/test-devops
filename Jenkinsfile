// ===================================================================
// BÀI 2 - Jenkins: BUILD -> TEST -> PUSH -> PULL -> DEPLOY
// (buổi 7 thêm: -> DEPLOY ĐA SERVER bằng Ansible)
// ===================================================================
// Jenkins chạy trong container trên laptop, deploy ngược ra chính laptop
// qua /var/run/docker.sock (cách dựng: xem huong-dan-jenkins.md).
//
// ===== VÒNG CI/CD ĐẦY ĐỦ (bước 7-8, xem huong-dan-ansible.md) =====
//   git push
//     -> Jenkins pollSCM phát hiện commit mới (2 phút/lần)
//     -> build + test + push image lên GHCR
//     -> Ansible deploy image đó lên web1, LẦN LƯỢT rồi tới web2
//     -> xác nhận cả hai server chạy đúng image vừa build
//
// Vì sao Jenkins làm được mà GitHub Actions không?
//   Runner của GitHub ở trên cloud, không SSH vào được web1/web2 trên
//   laptop bạn. Jenkins chạy ngay trong máy, cùng mạng ansible-labnet
//   với chúng -> demo trọn vòng không cần server thật.
//
// Yêu cầu trước khi chạy bước 7:
//   1. cd ansible/lab && ./setup-lab.sh        (dựng web1, web2)
//   2. cd ansible && ansible-playbook playbooks/02-install-docker.yml
//   3. Jenkins có credential 'ansible-lab-key' = file ~/.ssh/ansible_lab
//
// Ba nguyên tắc:
//
// 1) BUILD MỘT LẦN cho mỗi kiến trúc, KHÔNG build lại khi deploy.
//
// 2) IMAGE ĐA KIẾN TRÚC (amd64 + arm64)
//    Cùng 1 tag chạy được trên Mac M-series, PC Intel/AMD, Docker Desktop
//    Windows/Linux và server cloud.
//
// 3) TEST TRÊN KIẾN TRÚC MÁY MÌNH
//    Build bản native của laptop trước để test (nhanh, không giả lập),
//    test đạt rồi mới build tiếp bản đa kiến trúc để push.
// ===================================================================

pipeline {
  agent any

  environment {
    REGISTRY   = 'ghcr.io'
    // ĐỔI thành tài khoản GitHub của bạn (BẮT BUỘC viết thường)
    IMAGE_NAME = 'vuanhtuanvn85/test-devops'
    IMAGE      = "${REGISTRY}/${IMAGE_NAME}"

    // Credential kiểu "Username with password":
    //   user     = tên GitHub
    //   password = Personal Access Token có quyền write:packages
    GHCR_CREDS = credentials('ghcr-credentials')

    // Các kiến trúc sẽ push lên registry
    PLATFORMS = 'linux/amd64,linux/arm64'

    // Cache build lưu ngay trên registry (tag riêng ":buildcache").
    // KHÔNG dùng thư mục local: builder "docker-container" chạy trong container
    // BuildKit riêng, thư mục /tmp của nó không phải /tmp của Jenkins,
    // và volume mount vào thuộc quyền root nên jenkins không ghi được.
    CACHE_TAG = "${REGISTRY}/${IMAGE_NAME}:buildcache"

    // Cổng stack deploy thật (khác cổng smoke test 3999/55999 để không đụng nhau)
    DEPLOY_WEB_PORT = '3000'
    DEPLOY_DB_PORT  = '5432'
    DEPLOY_PROJECT  = 'dictionary-prod'

    // ===== Deploy đa server bằng Ansible (thêm ở buổi 7) =====
    // Khóa riêng SSH để vào web1/web2. Credential kiểu "SSH Username with
    // private key", ID 'ansible-lab-key' — nội dung là file ~/.ssh/ansible_lab
    // do ansible/lab/setup-lab.sh sinh ra.
    //
    // Vì sao không đọc thẳng ~/.ssh/ansible_lab? Vì Jenkins chạy TRONG
    // container, home của nó là /var/jenkins_home — không thấy ~/.ssh của
    // laptop. Khóa phải đi qua credential store.
    ANSIBLE_KEY = credentials('ansible-lab-key')

    // Tắt kiểm tra host key: lab dựng lại thì host key đổi, mà Jenkins chạy
    // không có người bấm "yes". CHỈ dùng khi học.
    ANSIBLE_HOST_KEY_CHECKING = 'False'

    // Cổng web1/web2 forward ra laptop — dùng ở stage kiểm tra.
    WEB1_PORT = '2201'
    WEB2_PORT = '2202'
  }

  options {
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '10'))   // giữ 10 bản gần nhất để rollback
  }

  triggers {
    // Laptop không có IP public nên GitHub không gọi webhook vào được
    // -> Jenkins chủ động hỏi 2 phút/lần xem có commit mới không.
    pollSCM('H/2 * * * *')
  }

  stages {

    // ---------- Chuẩn bị: tag + máy build đa kiến trúc ----------
    stage('Chuẩn bị') {
      steps {
        script {
          env.SHA_SHORT  = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.TAG_SHA    = "${IMAGE}:${env.SHA_SHORT}"
          env.TAG_LATEST = "${IMAGE}:latest"
          // Kiến trúc của chính máy Jenkins đang chạy (arm64 trên Mac M-series)
          env.NATIVE_ARCH = sh(
            script: "docker version --format '{{.Server.Arch}}'",
            returnStdout: true
          ).trim()
        }

        echo "Image     : ${env.TAG_SHA}"
        echo "Máy này   : linux/${env.NATIVE_ARCH}"
        echo "Sẽ push   : ${PLATFORMS}"

        // Đăng nhập NGAY từ đầu vì stage BUILD đã cần ghi cache lên registry.
        // --password-stdin: token không lộ trong log hay danh sách tiến trình.
        sh '''
          echo "$GHCR_CREDS_PSW" | docker login ${REGISTRY} -u "$GHCR_CREDS_USR" --password-stdin
        '''

        // QEMU: cho phép build kiến trúc khác với máy hiện tại (giả lập).
        // Buildx builder: bắt buộc để build nhiều kiến trúc cùng lúc,
        // vì builder mặc định của Docker chỉ làm được 1 kiến trúc.
        sh '''
          docker run --privileged --rm tonistiigi/binfmt --install all || true
          docker buildx create --name multiarch --driver docker-container --use 2>/dev/null \
            || docker buildx use multiarch
          docker buildx inspect --bootstrap
        '''
      }
    }

    // ---------- BƯỚC 1: BUILD ----------
    stage('1. BUILD') {
      steps {
        echo "=== Build bản native (linux/${env.NATIVE_ARCH}) để test ==="
        // --load nạp image vào Docker local để stage TEST dùng được ngay.
        // --load chỉ nhận 1 kiến trúc, nên bản đa kiến trúc để dành stage PUSH.
        //
        // Cache đẩy lên registry (tag :buildcache) để stage PUSH dùng lại,
        // không build lại từ đầu. Lần chạy sau cũng nhanh hơn nhờ cache này.
        //
        // Lần chạy ĐẦU TIÊN chưa có tag :buildcache trên registry:
        //   - cache-to  : ignore-error=true lo được (ghi lỗi thì bỏ qua)
        //   - cache-from: KHÔNG có ignore-error -> báo "not found" và HỎNG build
        // Nên phải kiểm tra tag tồn tại chưa rồi mới thêm --cache-from.
        sh """
          CACHE_FROM=""
          if docker buildx imagetools inspect ${CACHE_TAG} >/dev/null 2>&1; then
            CACHE_FROM="--cache-from type=registry,ref=${CACHE_TAG}"
            echo "Có cache trên registry -> dùng lại"
          else
            echo "Chưa có cache (lần chạy đầu) -> build từ đầu"
          fi

          docker buildx build \
            --platform linux/${env.NATIVE_ARCH} \
            --tag ${env.TAG_SHA} \
            \$CACHE_FROM \
            --cache-to type=registry,ref=${CACHE_TAG},mode=max,ignore-error=true \
            --load \
            .
        """
        sh "docker images ${IMAGE} --format 'table {{.Repository}}\\t{{.Tag}}\\t{{.Size}}'"
      }
    }

    // ---------- BƯỚC 2: TEST ----------
    stage('2. TEST') {
      steps {
        echo "=== Smoke test trên image vừa build ==="
        // SMOKE_IMAGE khiến script dùng docker-compose.prod.yml -> chạy đúng
        // image này, KHÔNG build lại.
        // BUILD_NUMBER làm tên compose project khác nhau mỗi lần -> chạy song song được.
        sh """
          chmod +x scripts/smoke-test.sh
          SMOKE_IMAGE=${env.TAG_SHA} ./scripts/smoke-test.sh
        """
      }
    }

    // ---------- BƯỚC 3: PUSH ----------
    stage('3. PUSH') {
      steps {
        echo "=== Build đa kiến trúc + đẩy lên ${REGISTRY} ==="
        // Không thể --load rồi --push bản multi-arch: buildx đẩy thẳng
        // "manifest list" (1 tag chứa nhiều kiến trúc) lên registry.
        // Bản native lấy lại từ cache (đúng layer vừa test), chỉ kiến trúc
        // còn lại phải build thêm.
        // Đã docker login ở stage Chuẩn bị nên không cần đăng nhập lại.
        // Cũng kiểm tra cache như stage BUILD: nếu stage BUILD ghi cache lỗi
        // thì tag :buildcache vẫn chưa tồn tại, --cache-from sẽ làm hỏng build.
        sh """
          CACHE_FROM=""
          if docker buildx imagetools inspect ${CACHE_TAG} >/dev/null 2>&1; then
            CACHE_FROM="--cache-from type=registry,ref=${CACHE_TAG}"
          fi

          docker buildx build \
            --platform ${PLATFORMS} \
            --tag ${env.TAG_SHA} \
            --tag ${env.TAG_LATEST} \
            \$CACHE_FROM \
            --cache-to type=registry,ref=${CACHE_TAG},mode=max,ignore-error=true \
            --push \
            .
        """

        echo "=== Xác nhận image có đủ các kiến trúc ==="
        sh """
          docker buildx imagetools inspect ${env.TAG_SHA} \
            --format '{{range .Manifest.Manifests}}{{.Platform.OS}}/{{.Platform.Architecture}}{{"\\n"}}{{end}}'
        """
      }
    }

    // ---------- BƯỚC 4: PULL ----------
    stage('4. PULL') {
      steps {
        echo "=== Kéo image từ registry về ==="
        // Xoá bản local trước rồi mới pull: ép Docker tải thật từ registry.
        // Nếu còn bản local, lệnh pull sẽ bỏ qua và ta không kiểm chứng được gì.
        // Docker tự chọn đúng bản linux/${env.NATIVE_ARCH} cho máy này.
        sh """
          docker rmi ${env.TAG_SHA} ${env.TAG_LATEST} 2>/dev/null || true
          docker pull ${env.TAG_SHA}
        """
        sh """
          echo "Kiến trúc của image vừa kéo về:"
          docker image inspect ${env.TAG_SHA} --format '{{.Os}}/{{.Architecture}}'
        """
      }
    }

    // ---------- BƯỚC 5: DEPLOY ----------
    stage('5. DEPLOY') {
      steps {
        echo "=== Deploy lên laptop, cổng ${DEPLOY_WEB_PORT} ==="
        // docker-compose.prod.yml dùng "image:" nên compose KHÔNG build lại,
        // chạy đúng image vừa kéo từ registry về.
        // Không dùng "down -v": giữ volume pgdata để dữ liệu sống qua các lần deploy.
        withEnv([
          "IMAGE_TAG=${env.TAG_SHA}",
          "WEB_PORT=${DEPLOY_WEB_PORT}",
          "DB_PORT=${DEPLOY_DB_PORT}",
          "POSTGRES_USER=dictuser",
          "POSTGRES_PASSWORD=dictpass",
          "POSTGRES_DB=dictionary"
        ]) {
          sh """
            docker compose -p ${DEPLOY_PROJECT} \
              -f docker-compose.yml -f docker-compose.prod.yml \
              up -d --remove-orphans
          """
        }
      }
    }

    // ---------- BƯỚC 6: Kiểm tra sau deploy ----------
    stage('6. Kiểm tra sau deploy') {
      steps {
        echo "=== Xác nhận app đang chạy thật ==="
        // Jenkins ở trong container, gọi ra host qua host.docker.internal
        sh """
          BASE=http://host.docker.internal:${DEPLOY_WEB_PORT}
          for i in \$(seq 1 30); do
            if curl -sf \$BASE/api/health >/dev/null 2>&1; then
              echo "App sẵn sàng sau \${i}s"
              curl -s \$BASE/api/health; echo ""
              curl -s \$BASE/api/define/computer; echo ""
              exit 0
            fi
            sleep 1
          done
          echo "TIMEOUT - app không phản hồi sau 30s"
          docker compose -p ${DEPLOY_PROJECT} logs web
          exit 1
        """
      }
    }

    // ---------- BƯỚC 7: DEPLOY ĐA SERVER BẰNG ANSIBLE ----------
    // Khác biệt với bước 5 — và đây là bài học chính của buổi này:
    //
    //   Bước 5: deploy 1 máy (laptop), bằng docker compose gọi trực tiếp.
    //           Đủ dùng khi có đúng một máy.
    //
    //   Bước 7: deploy N máy (web1, web2), bằng Ansible.
    //           Thêm server thứ 3 chỉ cần thêm 1 dòng vào inventory,
    //           pipeline KHÔNG phải sửa gì.
    //
    // Đó là lý do tồn tại của Ansible: cùng một mô tả trạng thái, áp lên
    // bao nhiêu máy cũng được.
    stage('7. DEPLOY ĐA SERVER (Ansible)') {
      steps {
        echo "=== Deploy ${env.TAG_SHA} lên web1 + web2 ==="

        // Lab còn chạy không? Không có thì bỏ qua cả stage thay vì làm
        // pipeline đỏ — lab là môi trường học, có thể đã bị dọn.
        script {
          env.LAB_SONG = sh(
            script: 'docker ps --format "{{.Names}}" | grep -q ansible-web1 && echo yes || echo no',
            returnStdout: true
          ).trim()
        }

        script {
          if (env.LAB_SONG != 'yes') {
            echo """
            BỎ QUA: không thấy container ansible-web1.
            Dựng lab trước:  cd ansible/lab && ./setup-lab.sh
            """
            return
          }

          dir('ansible') {
            // ANSIBLE_KEY là đường dẫn tới file khóa tạm do Jenkins tạo.
            // chmod 600: ssh TỪ CHỐI dùng khóa mà người khác đọc được
            // ("UNPROTECTED PRIVATE KEY FILE"). Jenkins không tự set quyền này.
            sh '''
              cp "$ANSIBLE_KEY" /tmp/ansible_lab_key
              chmod 600 /tmp/ansible_lab_key
            '''

            // Deploy lần đầu: 03 tạo thư mục, .env, db, compose files.
            // Idempotent nên chạy lại vô hại — lần sau chỉ sinh .env mới.
            //
            // Vì sao vẫn cần 03 khi đã có 04? Vì 04 chỉ recreate service
            // "web", nó giả định db và .env đã tồn tại. Server mới tinh
            // chưa có gì thì 04 sẽ dừng ở task assert.
            sh """
              ansible-playbook \
                -i inventory/hosts-ci.ini \
                playbooks/03-deploy-app.yml \
                -e image_tag=${env.TAG_SHA} \
                -e ansible_ssh_private_key_file=/tmp/ansible_lab_key
            """

            // Rolling update: web1 xong và KHỎE rồi mới sang web2.
            // Chạy ngay sau 03 để minh họa — thực tế các lần deploy sau
            // chỉ cần chạy 04 là đủ.
            sh """
              ansible-playbook \
                -i inventory/hosts-ci.ini \
                playbooks/04-rolling-update.yml \
                -e image_tag=${env.TAG_SHA} \
                -e ansible_ssh_private_key_file=/tmp/ansible_lab_key
            """
          }
        }
      }
      post {
        // Xoá khóa khỏi workspace dù thành công hay thất bại.
        always {
          sh 'rm -f /tmp/ansible_lab_key || true'
        }
      }
    }

    // ---------- BƯỚC 8: Xác nhận CẢ HAI server chạy đúng image ----------
    // Deploy báo thành công chưa đủ. Phải tự gọi vào từng server để chắc
    // chắn chúng cùng chạy đúng bản vừa build — không phải bản cũ còn sót.
    stage('8. Kiểm tra web1 + web2') {
      when {
        expression { env.LAB_SONG == 'yes' }
      }
      steps {
        echo "=== Gọi vào từng server xác nhận ==="
        // Gọi qua host.docker.internal: cổng 2201/2202 được lab forward ra
        // laptop, còn app trong web1/web2 nghe cổng 3000 nội bộ.
        // Ở đây ta SSH vào rồi curl từ bên trong, giống cách playbook làm.
        sh """
          for srv in ansible-web1 ansible-web2; do
            echo "--- \$srv ---"
            docker exec \$srv curl -sf http://localhost:${DEPLOY_WEB_PORT}/api/health \
              || { echo "LỖI: \$srv không trả lời /api/health"; exit 1; }
            echo ""
            docker exec \$srv curl -sf http://localhost:${DEPLOY_WEB_PORT}/api/define/computer \
              | grep -q "máy tính" \
              || { echo "LỖI: \$srv tra từ sai"; exit 1; }
            echo "  tra từ OK"

            # Xác nhận đúng image vừa build, không phải bản cũ
            CHAY=\$(docker exec \$srv docker inspect --format '{{.Config.Image}}' \
                     \$(docker exec \$srv docker ps -qf name=web | head -1))
            echo "  image đang chạy: \$CHAY"
            [ "\$CHAY" = "${env.TAG_SHA}" ] \
              || { echo "LỖI: \$srv chạy \$CHAY, mong đợi ${env.TAG_SHA}"; exit 1; }
          done
          echo ""
          echo "CẢ HAI SERVER đang chạy ${env.TAG_SHA}"
        """
      }
    }
  }

  post {
    success {
      echo """
      =====================================================
      THÀNH CÔNG
        Image    : ${env.TAG_SHA}
        Kiến trúc: ${PLATFORMS}
        Ứng dụng : http://localhost:${DEPLOY_WEB_PORT}  (laptop, bước 5)
        web1     : http://localhost:${WEB1_PORT}  (SSH) — app ở cổng ${DEPLOY_WEB_PORT} nội bộ
        web2     : http://localhost:${WEB2_PORT}  (SSH) — app ở cổng ${DEPLOY_WEB_PORT} nội bộ

      Rollback ĐA SERVER về bản trước (thay <sha_cũ>) — cũng rolling, không downtime:
        cd ansible && ansible-playbook -i inventory/hosts-ci.ini \\
          playbooks/04-rolling-update.yml -e image_tag=${IMAGE}:<sha_cũ>

      Rollback stack trên laptop (thay <sha_cũ>):
        IMAGE_TAG=${IMAGE}:<sha_cũ> WEB_PORT=${DEPLOY_WEB_PORT} DB_PORT=${DEPLOY_DB_PORT} \\
        POSTGRES_USER=dictuser POSTGRES_PASSWORD=dictpass POSTGRES_DB=dictionary \\
        docker compose -p ${DEPLOY_PROJECT} \\
          -f docker-compose.yml -f docker-compose.prod.yml up -d
      =====================================================
      """
    }
    failure {
      echo "THẤT BẠI - stack đang chạy KHÔNG bị đụng tới (deploy chỉ chạy sau khi test đạt)."
    }
    always {
      sh 'docker logout ${REGISTRY} || true'
      // Dọn image cũ hơn 7 ngày để laptop không đầy ổ
      sh 'docker image prune -f --filter "until=168h" || true'
    }
  }
}
