#!/usr/bin/env bash
# Smoke test: dựng nguyên stack lên rồi kiểm tra các API trả đúng.
# Dùng cho cả CI lẫn chạy tay ở máy.
#
#   ./scripts/smoke-test.sh                       # tự build từ source (chạy tay ở máy)
#   SMOKE_IMAGE=ghcr.io/u/app:abc123 ./scripts/smoke-test.sh   # test image có sẵn (CI)
#
# Đặt SMOKE_IMAGE để test đúng image đã build trước đó, thay vì build lại.
# Đây là điểm mấu chốt của CI: image được test phải LÀ image sẽ deploy.
#
# Thoát mã 0 = tất cả đạt, khác 0 = có test hỏng.

set -euo pipefail

cd "$(dirname "$0")/.."

# Cổng riêng cho test, tránh đụng stack đang chạy ở máy
export WEB_PORT=${SMOKE_WEB_PORT:-3999}
export DB_PORT=${SMOKE_DB_PORT:-55999}
export POSTGRES_USER=${POSTGRES_USER:-testuser}
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-testpass}
export POSTGRES_DB=${POSTGRES_DB:-testdict}

# Tên project khác nhau cho mỗi lần chạy song song (Jenkins chạy nhiều job cùng lúc).
# Chạy tay không có 2 biến này thì vẫn là "dictsmoke" như cũ.
PROJECT="dictsmoke${BUILD_NUMBER:-${GITHUB_RUN_ID:-}}"
COMPOSE="docker compose -p $PROJECT"
BASE="http://localhost:${WEB_PORT}"

# Có SMOKE_IMAGE -> dùng file prod (chỉ pull/chạy image), không build.
# Không có     -> dùng compose thường (build từ source) như trước nay.
if [[ -n "${SMOKE_IMAGE:-}" ]]; then
  export IMAGE_TAG="$SMOKE_IMAGE"
  COMPOSE="$COMPOSE -f docker-compose.yml -f docker-compose.prod.yml"
  UP_ARGS="-d"
  echo "=== Chế độ: test image có sẵn -> $SMOKE_IMAGE"
else
  UP_ARGS="--build -d"
  echo "=== Chế độ: build từ source"
fi

PASS=0
FAIL=0

cleanup() {
  echo ""
  echo "--- dọn dẹp ---"
  $COMPOSE down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

check() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $name"
    echo "        mong đợi chứa: $expected"
    echo "        nhận được:     $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Dựng stack (cổng $WEB_PORT) ==="
$COMPOSE down -v >/dev/null 2>&1 || true
$COMPOSE up $UP_ARGS

echo ""
echo "=== Chờ web sẵn sàng ==="
for i in $(seq 1 30); do
  if curl -sf "$BASE/api/health" >/dev/null 2>&1; then
    echo "  sẵn sàng sau ${i}s"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "  TIMEOUT sau 30s - log của web:"
    $COMPOSE logs web
    exit 1
  fi
  sleep 1
done

echo ""
echo "=== Kiểm tra API ==="

check "health báo đã kết nối DB" \
  "$(curl -s "$BASE/api/health")" '"db":"connected"'

check "health đếm đúng 10 từ" \
  "$(curl -s "$BASE/api/health")" '"words":10'

check "danh sách từ có 'computer'" \
  "$(curl -s "$BASE/api/words")" 'computer'

check "tra 'computer' ra nghĩa tiếng Việt" \
  "$(curl -s "$BASE/api/define/computer")" 'máy tính'

check "tra chữ hoa 'APPLE' vẫn ra kết quả" \
  "$(curl -s "$BASE/api/define/APPLE")" 'quả táo'

check "từ không tồn tại trả HTTP 404" \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/define/khongtontai")" '404'

check "trang chủ trả HTTP 200" \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")" '200'

check "database có bảng words" \
  "$($COMPOSE exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc 'SELECT count(*) FROM words;')" '10'

echo ""
echo "=== Kết quả: $PASS đạt, $FAIL hỏng ==="
[[ $FAIL -eq 0 ]]
