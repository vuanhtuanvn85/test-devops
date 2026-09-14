// ===================================================================
// BÀI 2 - Jenkins: BUILD -> TEST -> PUSH -> PULL -> DEPLOY
// ===================================================================
// Jenkins chạy trong container trên laptop, deploy ngược ra chính laptop
// qua /var/run/docker.sock (cách dựng: xem huong-dan-jenkins.md).
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
  }

  post {
    success {
      echo """
      =====================================================
      THÀNH CÔNG
        Image    : ${env.TAG_SHA}
        Kiến trúc: ${PLATFORMS}
        Ứng dụng : http://localhost:${DEPLOY_WEB_PORT}

      Rollback về bản trước (thay <sha_cũ>):
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
