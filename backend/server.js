const express = require('express');
const path = require('path');
const pool = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;

// ===================================================================
// ACCESS LOG — ghi lại MỌI request
// ===================================================================
// Vì sao cần? Không có nó, `docker logs` chỉ hiện đúng một dòng
// "Server đang chạy..." lúc khởi động. Tra từ cả trăm lần cũng không
// sinh thêm dòng nào -> không biết app có nhận được request không,
// request nào chậm, request nào lỗi.
//
// VỊ TRÍ QUAN TRỌNG: middleware phải đặt TRƯỚC mọi app.get(...).
// Express chạy middleware theo đúng thứ tự khai báo; đặt sau route thì
// request đã được trả về rồi, middleware không bao giờ chạy tới.
//
// Dùng res.on('finish') thay vì log ngay: lúc đó mới biết status code
// và tính được thời gian xử lý thật.
//
// TÊN SERVER: in ra để biết server NÀO trả lời. Khi có 2 server trở lên,
// đây là thứ giúp phân biệt log của web1 với web2.
//
// Ưu tiên biến SERVER_NAME (Ansible điền từ inventory: web1, web2...).
// Không có thì lùi về hostname của container.
//
// Vì sao không dùng thẳng os.hostname()? Trong container nó là ID ngẫu
// nhiên kiểu "c80e68fabcd0" và ĐỔI sau mỗi lần deploy -> xem log không
// biết là máy nào.
const os = require('os');
const HOSTNAME = process.env.SERVER_NAME || os.hostname();

app.use((req, res, next) => {
  const batDau = Date.now();
  res.on('finish', () => {
    const thoiGian = Date.now() - batDau;
    console.log(
      `[${new Date().toISOString()}] ${HOSTNAME} ` +
      `${req.method} ${req.originalUrl} ${res.statusCode} ${thoiGian}ms`
    );
  });
  next();
});

// LIVENESS probe (Kubernetes): "tiến trình Node còn sống không?"
// Luôn trả 200 nếu server còn chạy - KHÔNG hỏi database.
//
// Vì sao tách khỏi /api/health? Liveness hỏng => K8s GIẾT container và khởi động lại.
// Nếu liveness đi hỏi database, lúc db khởi động chậm thì web bị restart liên tục
// (CrashLoopBackOff) dù bản thân nó hoàn toàn khoẻ. Restart web không sửa được db.
app.get('/healthz', (req, res) => {
  res.json({ status: 'ok' });
});

// API: kiểm tra kết nối database (dùng cho badge trạng thái trên web)
// Kiêm luôn READINESS probe (Kubernetes): "pod này nhận request được chưa?"
// Readiness hỏng => K8s chỉ GỠ pod khỏi Service, không giết. Đúng với trường hợp
// db chưa sẵn sàng: chờ db lên là pod tự được nhận request trở lại.
// Trả 503 khi mất db chính là điều readiness cần.
app.get('/api/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT COUNT(*) FROM words');
    res.json({ db: 'connected', words: Number(result.rows[0].count) });
  } catch (err) {
    res.status(503).json({ db: 'disconnected', error: err.message });
  }
});

// API: lấy danh sách từ (để đổ vào listbox)
app.get('/api/words', async (req, res) => {
  try {
    const result = await pool.query('SELECT word FROM words ORDER BY word');
    res.json(result.rows.map((row) => row.word));
  } catch (err) {
    res.status(503).json({ error: 'Không truy vấn được database' });
  }
});

// API: tra nghĩa 1 từ cụ thể
app.get('/api/define/:word', async (req, res) => {
  const word = req.params.word.toLowerCase();
  try {
    const result = await pool.query(
      'SELECT word, definition FROM words WHERE word = $1',
      [word]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Không tìm thấy từ này' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    res.status(503).json({ error: 'Không truy vấn được database' });
  }
});

// Phục vụ file tĩnh của React (đã build sẵn vào thư mục public)
app.use(express.static(path.join(__dirname, 'public')));

// Mọi route khác trả về index.html (để React Router hoạt động nếu sau này mở rộng)
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`Server đang chạy tại http://localhost:${PORT} (container ${HOSTNAME})`);
});
