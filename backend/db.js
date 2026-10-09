const { Pool } = require('pg');

// DB_HOST là "db" - tên service trong docker-compose.yml, KHÔNG phải localhost.
// Docker Compose tự tạo DNS nội bộ để các container gọi nhau bằng tên service.
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'dictionary',
});

// BẮT BUỘC: xử lý lỗi của kết nối ĐANG RỖI trong pool.
//
// Vì sao? pg giữ sẵn vài kết nối rảnh để tái sử dụng. Khi database đóng chúng lại
// (restart, bảo trì, hết idle timeout, mạng chập chờn), pool phát ra sự kiện 'error'.
// Node có quy tắc: sự kiện 'error' KHÔNG ai lắng nghe => ném exception và GIẾT tiến trình.
//
// Thiếu đoạn này, chỉ cần database restart một lần là web sập theo:
//   error: terminating connection due to administrator command
//   Emitted 'error' event on BoundPool instance  -> exit code 1
//
// Trên Docker Compose ít thấy vì hiếm khi restart riêng db. Trên Kubernetes thì pod
// bị thay thường xuyên (rolling update, dời node, scale), nên lỗi này lộ ra ngay.
//
// Chỉ cần ghi log là đủ: pool tự bỏ kết nối hỏng và mở kết nối mới ở lần query sau.
pool.on('error', (err) => {
  console.error('Kết nối rỗi tới database gặp lỗi (pool sẽ tự mở lại):', err.message);
});

module.exports = pool;
