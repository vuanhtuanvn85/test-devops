// Backend phiên bản GỐC - đọc từ điển từ file JS, không cần database.
// Dùng cho Phần 2 (npm) và Phần 3 (Dockerfile) của bài lab.

const express = require('express');
const path = require('path');
const dictionary = require('./dictionary');

const app = express();
const PORT = process.env.PORT || 3000;

// API: kiểm tra nguồn dữ liệu (đối chiếu với /api/health ở Phần 4)
app.get('/api/health', (req, res) => {
  res.json({ source: 'file js', words: Object.keys(dictionary).length });
});

// API: lấy danh sách từ (để đổ vào listbox)
app.get('/api/words', (req, res) => {
  res.json(Object.keys(dictionary));
});

// API: tra nghĩa 1 từ cụ thể
app.get('/api/define/:word', (req, res) => {
  const word = req.params.word.toLowerCase();
  const definition = dictionary[word];
  if (!definition) {
    return res.status(404).json({ error: 'Không tìm thấy từ này' });
  }
  res.json({ word, definition });
});

// Phục vụ file tĩnh của React (đã build sẵn vào thư mục public)
app.use(express.static(path.join(__dirname, 'public')));

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`Server đang chạy tại http://localhost:${PORT}`);
});
