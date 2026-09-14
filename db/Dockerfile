# Image database có sẵn schema + dữ liệu mẫu bên trong.
#
# VÌ SAO CẦN FILE NÀY (thay vì dùng thẳng postgres:16-alpine)?
#
# docker-compose.yml gốc nạp init.sql bằng bind mount:
#     - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
#
# Cách đó chạy tốt ở máy dev, nhưng HỎNG khi Jenkins chạy trong container mà
# điều khiển Docker của host (kiểu DooD - Docker outside of Docker):
# đường dẫn "./db/init.sql" được daemon hiểu là đường dẫn TRÊN HOST, trong khi
# workspace Jenkins (/var/jenkins_home/...) chỉ tồn tại bên trong container.
# Docker không thấy file -> mount vào thư mục rỗng -> Postgres bỏ qua init
# -> lỗi 'relation "words" does not exist'.
#
# COPY thì khác: file được đóng gói vào image lúc build, không phụ thuộc
# đường dẫn lúc chạy. Nhờ vậy chạy đúng ở mọi môi trường.

FROM postgres:16-alpine

# Postgres tự chạy mọi file .sql trong thư mục này ở LẦN KHỞI TẠO ĐẦU TIÊN,
# khi thư mục dữ liệu còn rỗng. Volume đã có dữ liệu thì file này bị bỏ qua.
COPY init.sql /docker-entrypoint-initdb.d/init.sql
