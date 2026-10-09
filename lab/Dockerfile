# Dockerfile cho Phần 3 của bài lab: từ điển đọc từ file JS, KHÔNG cần database.
# Build từ thư mục gốc dự án:
#   docker build -f lab/Dockerfile -t dictionary-lab:v1 .

# ===== Stage 1: Build React frontend =====
FROM node:20-alpine AS frontend-build
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

# ===== Stage 2: Backend (bản file JS) + frontend đã build =====
FROM node:20-alpine
WORKDIR /app
COPY lab/backend/package*.json ./
RUN npm install --omit=dev
COPY lab/backend/ ./
COPY --from=frontend-build /app/frontend/dist ./public

EXPOSE 3000
CMD ["node", "server.js"]
