# BÀI 3 — Kubernetes: TỪ DOCKER COMPOSE LÊN CLUSTER

> Mục tiêu: chạy đúng ứng dụng từ điển của các buổi trước trên Kubernetes.
> Backend **không sửa một dòng code nào**. Thứ thay đổi chỉ là cách mô tả hạ tầng.

---

## 1. Vì sao cần Kubernetes khi đã có Docker Compose?

Compose làm rất tốt việc chạy nhiều container **trên một máy**. Nó dừng lại ở đó.

| Tình huống thật | Docker Compose | Kubernetes |
|---|---|---|
| Container chết lúc 2 giờ sáng | `restart:` bật lại, nhưng nếu cả máy chết thì hết | Lên lịch lại pod sang node khác |
| Tết, lượng truy cập tăng 10 lần | Sửa file, chạy lại tay | HPA tự thêm pod theo tải |
| Deploy bản mới, không được downtime | `up -d` = dừng cũ, dựng mới → đứt vài giây | Rolling update, luôn còn pod phục vụ |
| Bản mới lỗi, cần quay lại ngay | Tự tìm image cũ, chạy lại tay | `kubectl rollout undo`, vài giây |
| Chạy trên 20 máy chủ | Không làm được | Đúng việc của nó |

Kubernetes đắt hơn về độ phức tạp. Đổi lại ta có **hệ thống tự điều khiển**.

### Ý tưởng cốt lõi: khai báo, không ra lệnh

Đây là điều khác biệt lớn nhất, phải hiểu trước khi gõ lệnh nào.

```
Docker Compose:  "Hãy CHẠY 2 container"          → mệnh lệnh, làm một lần
Kubernetes:      "Tôi MUỐN LUÔN CÓ 2 pod chạy"   → trạng thái mong muốn
```

Bạn khai báo trạng thái mong muốn. Một vòng lặp trong cluster liên tục so sánh
**thực tế** với **mong muốn**, thấy lệch là tự sửa. Xoá một pod đi, nó tạo pod mới
— không phải vì ai đó ra lệnh, mà vì thực tế (1 pod) đang lệch mong muốn (2 pod).

Hệ quả thực tế: **đừng sửa trực tiếp trên cluster**. Sửa file YAML rồi `apply`.
File YAML mới là nguồn sự thật.

---

## 2. Bảng đối chiếu Compose → Kubernetes

Học K8s dễ nhất bằng cách quy chiếu về thứ đã biết:

| `docker-compose.yml` | Kubernetes | File trong `k8s/` |
|---|---|---|
| `services: web` | Deployment + Pod | `20-web-deployment.yaml` |
| `services: db` | StatefulSet | `11-db-statefulset.yaml` |
| `ports: "3000:3000"` | Service (NodePort) | `21-web-service.yaml` |
| gọi nhau bằng tên `db` | Service + DNS nội bộ | `12-db-service.yaml` |
| `environment:` | ConfigMap | `01-configmap.yaml` |
| mật khẩu trong `.env` | Secret | `02-secret.yaml` |
| `volumes: pgdata` | PVC (volumeClaimTemplates) | trong `11-...` |
| mount `init.sql` | ConfigMap mount thành file | `10-db-init-configmap.yaml` |
| `healthcheck:` | readinessProbe / livenessProbe | trong `11-`, `20-` |
| `depends_on: service_healthy` | initContainer `wait-for-db` | trong `20-...` |
| `restart: unless-stopped` | ReplicaSet tự hồi phục (mặc định) | — |
| `-p <project>` | Namespace | `00-namespace.yaml` |
| *không có* | Ingress (định tuyến theo domain) | `22-web-ingress.yaml` |
| *không có* | HPA (tự scale theo tải) | `23-web-hpa.yaml` |

> **Điểm đáng chú ý nhất của cả bài:** trong `backend/db.js`, biến `DB_HOST` vẫn là
> `"db"` — y hệt bản Compose. Kubernetes cũng có DNS nội bộ, nên code không cần biết
> nó đang chạy trên Compose hay trên cluster. Hạ tầng thay đổi, ứng dụng thì không.

---

## 3. Kiến trúc cluster

```
        kubectl  (máy của bạn)
           │  gửi YAML qua HTTPS
           ▼
   ┌───────────────────────── CONTROL PLANE ─────────────────────────┐
   │  API Server   — cửa duy nhất vào cluster, xác thực & lưu trữ     │
   │  etcd         — cơ sở dữ liệu ghi mọi trạng thái                 │
   │  Scheduler    — chọn node phù hợp để đặt pod                     │
   │  Controller   — vòng lặp so "thực tế" với "mong muốn", tự sửa    │
   └──────────────────────────────┬───────────────────────────────────┘
                                  │
   ┌──────────────────────────────▼─────── WORKER NODE ───────────────┐
   │  kubelet     — nhận lệnh, bảo container runtime chạy container   │
   │  kube-proxy  — định tuyến mạng cho Service                       │
   │                                                                   │
   │   ┌─── Pod: web ────┐  ┌─── Pod: web ────┐  ┌─── Pod: db-0 ───┐  │
   │   │ container web   │  │ container web   │  │ postgres        │  │
   │   │ :3000           │  │ :3000           │  │ :5432 + ổ đĩa   │  │
   │   └─────────────────┘  └─────────────────┘  └─────────────────┘  │
   └───────────────────────────────────────────────────────────────────┘
```

**Pod** là đơn vị nhỏ nhất K8s quản lý — không phải container. Một pod chứa một
hoặc vài container dùng chung mạng và ổ đĩa. Ở bài này mỗi pod đúng một container.

Pod là thứ **dùng rồi bỏ**: chết đi sinh lại là đổi tên, đổi IP. Vì vậy không bao
giờ gọi pod trực tiếp — luôn gọi qua Service.

---

## 4. Chuẩn bị cluster

### Cách 1 — Docker Desktop (khuyến nghị cho lớp học)

Đã cài Docker từ buổi trước nên không phải cài thêm gì:

```
Docker Desktop → Settings → Kubernetes → tick "Enable Kubernetes" → Apply & restart
```

Chờ 2–5 phút lần đầu. Ưu điểm lớn nhất: image build ở máy **dùng được ngay**,
không phải đẩy lên registry.

### Cách 2 — kind (nếu muốn cluster nhiều node)

```bash
brew install kind
kind create cluster --name dictionary
```

Với kind phải nạp image vào cluster sau mỗi lần build:

```bash
kind load docker-image dictionary-app-5:local --name dictionary
```

### Kiểm tra cluster đã sẵn sàng

```bash
kubectl cluster-info
kubectl get nodes
```

Phải thấy node ở trạng thái `Ready`:

```
NAME             STATUS   ROLES           AGE   VERSION
docker-desktop   Ready    control-plane   2m    v1.34.1
```

> Nếu báo `connection refused` là cluster chưa chạy. Kiểm tra `kubectl config current-context`.

---

## 5. Thực hành

### Bước 1 — Build image ở máy

```bash
cd "buoi 7/dictionary-app-5"
docker build -t dictionary-app-5:local .
```

Tag `:local` khớp với `image:` trong `k8s/20-web-deployment.yaml`.

Vì sao dùng image local mà không pull từ GHCR? Để tách bạch bài học: buổi này học
K8s, không lệ thuộc mạng và đăng nhập registry. Mục 8 sẽ chuyển sang tag từ CI.

> **Với kind** phải nạp thêm: `kind load docker-image dictionary-app-5:local --name dictionary`

### Bước 2 — Triển khai toàn bộ

```bash
kubectl apply -f k8s/
```

`apply -f` một thư mục sẽ áp dụng mọi file theo thứ tự tên — đó là lý do các file
được đánh số `00-`, `01-`, `10-`...

Kết quả mong đợi:

```
namespace/dictionary created
configmap/dictionary-config created
secret/dictionary-secret created
configmap/db-init created
statefulset.apps/db created
service/db created
deployment.apps/web created
service/web created
```

> Ingress (`22-`) và HPA (`23-`) cần cài thêm thành phần — xem mục 7. Chưa cài thì
> chúng vẫn được tạo nhưng không hoạt động, không ảnh hưởng phần còn lại.

### Bước 3 — Theo dõi quá trình khởi động

```bash
kubectl get pods -n dictionary -w
```

`-w` = watch, xem trạng thái đổi theo thời gian thực (Ctrl-C để thoát):

```
NAME                   READY   STATUS     RESTARTS   AGE
db-0                   0/1     Pending    0          0s
db-0                   0/1     ContainerCreating  0  2s
db-0                   1/1     Running    0          12s
web-6d4f8b9c7-x2kfp    0/1     Init:0/1   0          0s     ← initContainer đang chờ db
web-6d4f8b9c7-x2kfp    0/1     PodInitializing 0     14s    ← db xong, web bắt đầu
web-6d4f8b9c7-x2kfp    1/1     Running    0          18s
```

Hãy để sinh viên quan sát kỹ `Init:0/1`: đó là initContainer `wait-for-db` đang
làm đúng việc của `depends_on: service_healthy` bên Compose.

Chú ý cột **READY `1/1`** khác cột **STATUS `Running`**:
- `Running` = container đã chạy
- `1/1` = readinessProbe đã đạt, pod **mới được** nhận request

Pod `Running` nhưng `0/1` là pod chưa sẵn sàng phục vụ — phân biệt được hai cột này
là hiểu được phần lớn việc chẩn đoán lỗi trên K8s.

### Bước 4 — Mở ứng dụng

```bash
open http://localhost:30080
```

Badge phải hiện **"Database: đã kết nối (10 từ)"**. Chọn từ trong danh sách, nghĩa
tiếng Việt hiện ra — y hệt bản Compose, nhưng giờ chạy trên cluster.

30080 là `nodePort` khai trong `k8s/21-web-service.yaml`.

Cách thứ hai, không cần NodePort:

```bash
kubectl port-forward -n dictionary svc/web 8080:3000
# rồi mở http://localhost:8080
```

`port-forward` tạo đường hầm tạm từ máy bạn vào cluster. Rất hay dùng để gỡ lỗi
những service không mở ra ngoài (ví dụ nối DBeaver thẳng vào Postgres).

---

## 6. Bộ lệnh `kubectl` sống còn

Đặt namespace mặc định để khỏi gõ `-n dictionary` mỗi lần:

```bash
kubectl config set-context --current --namespace=dictionary
```

### Xem

```bash
kubectl get pods                    # danh sách pod
kubectl get all                     # mọi thứ trong namespace
kubectl get pods -w                 # theo dõi thay đổi thời gian thực
kubectl get pods -o wide            # thêm IP và node
kubectl describe pod <tên-pod>      # chi tiết + EVENTS (quan trọng nhất khi gỡ lỗi)
```

> **Quy tắc số 1 khi gỡ lỗi:** pod không lên thì chạy `kubectl describe pod` và đọc
> phần **Events** ở cuối. 90% nguyên nhân nằm ở đó.

### Log

```bash
kubectl logs <tên-pod>              # log hiện tại
kubectl logs <tên-pod> -f           # bám theo (như tail -f)
kubectl logs <tên-pod> --previous   # log của lần chạy TRƯỚC khi crash  ← rất hay dùng
kubectl logs -l app=web --all-containers  # gộp log mọi pod có nhãn app=web
```

`--previous` là chìa khoá khi pod bị `CrashLoopBackOff`: container hiện tại vừa sinh
ra nên log rỗng, nguyên nhân nằm ở lần chạy trước.

### Vào trong container

```bash
kubectl exec -it <tên-pod> -- sh
kubectl exec -it db-0 -- psql -U dictuser -d dictionary
```

### Sửa và xoá

```bash
kubectl apply -f k8s/                          # áp dụng thay đổi
kubectl scale deployment/web --replicas=4      # đổi số pod
kubectl rollout restart deployment/web         # khởi động lại toàn bộ pod
kubectl delete namespace dictionary            # xoá sạch bài thực hành
```

---

## 7. Thành phần tuỳ chọn

### Ingress (thay cho NodePort)

```bash
# Docker Desktop
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
# minikube
minikube addons enable ingress

echo "127.0.0.1 dictionary.local" | sudo tee -a /etc/hosts
```

Mở http://dictionary.local — không cần nhớ cổng 30080 nữa.

### HPA (tự scale theo tải)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Docker Desktop/kind dùng chứng chỉ tự ký nên phải thêm cờ này:
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl top pods -n dictionary     # kiểm tra đã đo được chưa
kubectl get hpa -n dictionary -w   # theo dõi HPA
```

Tạo tải để xem nó scale:

```bash
kubectl run tao-tai --rm -it --image=busybox -n dictionary -- \
  sh -c "while true; do wget -q -O- http://web:3000/api/words; done"
```

---

## 8. Bài tập kiểm chứng

> Tất cả bài tập dưới đây **đã được chạy thật** và kết quả ghi trong tài liệu này là
> output thực tế, không phải phỏng đoán.

### 8.1. Tự hồi phục — xoá pod xem nó sống lại

```bash
kubectl get pods -l app=web
kubectl delete pod -l app=web
sleep 10
kubectl get pods -l app=web
```

Kết quả: pod cũ `Terminating`, pod MỚI (tên khác) đã `Running`. Không ai ra lệnh tạo
lại — ReplicaSet thấy thực tế lệch mong muốn (2 pod) nên tự sửa.

### 8.2. Scale ngang

```bash
kubectl scale deployment/web --replicas=4
kubectl get pods -l app=web       # 4 pod
kubectl scale deployment/web --replicas=2
```

So sánh với Compose: phải sửa file rồi `up -d` lại.

### 8.3. PVC giữ dữ liệu — bài tập quan trọng nhất

```bash
# Thêm một từ mới vào database
kubectl exec db-0 -- psql -U dictuser -d dictionary \
  -c "INSERT INTO words (word,definition) VALUES ('kubernetes','hệ điều phối container');"

curl -s localhost:30080/api/health
# {"db":"connected","words":11}

# XOÁ hẳn pod database
kubectl delete pod db-0
kubectl wait --for=condition=ready pod/db-0 --timeout=180s

# Dữ liệu còn không?
curl -s localhost:30080/api/health
# {"db":"connected","words":11}          ← CÒN NGUYÊN
curl -s localhost:30080/api/define/kubernetes
# {"word":"kubernetes","definition":"hệ điều phối container"}
```

Pod bị xoá hoàn toàn, nhưng PVC `pgdata-db-0` sống độc lập với pod. Pod `db-0` sinh
lại gắn đúng ổ đĩa cũ. Đây là toàn bộ ý nghĩa của StatefulSet.

> Hỏi sinh viên: vì sao `init.sql` không chạy lại và ghi đè? Vì Postgres chỉ chạy
> `/docker-entrypoint-initdb.d/` khi thư mục dữ liệu **còn rỗng**. Ổ đĩa đã có dữ
> liệu nên nó bỏ qua.

### 8.4. Rolling update và rollback

```bash
# Sửa frontend/src/App.jsx: đổi tiêu đề thành "Tra từ điển Anh - Việt (v2)"
docker build -t dictionary-app-5:v2 .
kind load docker-image dictionary-app-5:v2 --name dictionary   # chỉ với kind

kubectl set image deployment/web web=dictionary-app-5:v2
kubectl rollout status deployment/web
```

Output thật cho thấy K8s thay pod **từng cái một**:

```
Waiting for deployment "web" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "web" rollout to finish: 1 old replicas are pending termination...
deployment "web" successfully rolled out
```

Nhờ `maxUnavailable: 0`, luôn còn pod phục vụ — **không downtime**.

```bash
kubectl rollout history deployment/web    # xem các revision
kubectl rollout undo deployment/web       # quay về bản trước
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'
# dictionary-app-5:local                  ← đã về bản cũ
```

> Muốn `rollout history` hiện lý do thay vì `<none>`, thêm:
> `kubectl annotate deployment/web kubernetes.io/change-cause="đổi tiêu đề v2"`

### 8.5. Liveness khác Readiness như thế nào

Đây là bài tập dạy được nhiều nhất. Giả lập database chết:

```bash
kubectl scale statefulset/db --replicas=0
sleep 30
kubectl get pods -l app=web
```

Kết quả thật:

```
NAME                   READY   STATUS    RESTARTS   AGE
web-7fd4697987-4f268   0/1     Running   0          60s
web-7fd4697987-mlmlz   0/1     Running   0          50s
```

Đọc kỹ ba cột:

| Quan sát | Nghĩa là |
|---|---|
| `STATUS: Running` | container vẫn sống |
| `READY: 0/1` | readiness (`/api/health`) hỏng → bị **gỡ khỏi Service**, không nhận request |
| `RESTARTS: 0` | liveness (`/healthz`) vẫn đạt → **không bị giết oan** |

Kiểm chứng endpoint đã bị gỡ:

```bash
kubectl get endpointslice -l kubernetes.io/service-name=web \
  -o jsonpath='{.items[0].endpoints[*].conditions.ready}'
# false false
```

Cho database sống lại:

```bash
kubectl scale statefulset/db --replicas=1
kubectl wait --for=condition=ready pod/db-0 --timeout=180s
sleep 12
kubectl get pods
```

```
db-0                   1/1     Running   0    18s
web-7fd4697987-4f268   1/1     Running   0    91s     ← RESTARTS vẫn 0
web-7fd4697987-mlmlz   1/1     Running   0    81s
```

Web **tự** READY trở lại mà không cần restart lần nào.

> **Bài học:** nếu liveness cũng trỏ vào `/api/health` (có hỏi database), thì db chết
> sẽ kéo theo web bị giết → restart → vẫn hỏng → `CrashLoopBackOff` vô tận, dù lỗi
> hoàn toàn nằm ở db. Restart web không bao giờ sửa được database hỏng.
>
> **Quy tắc:** liveness hỏi *"tiến trình tôi còn sống không?"*, readiness hỏi
> *"tôi phục vụ được chưa?"*. Liveness **không bao giờ** được phụ thuộc dịch vụ ngoài.

### 8.6. Cân bằng tải giữa các pod

```bash
for i in $(seq 1 6); do
  curl -s localhost:30080/api/health -o /dev/null -w "%{http_code} "
done; echo
kubectl logs -l app=web --all-containers --tail=20
```

Request được chia cho cả hai pod — Service làm cân bằng tải, không cần nginx.

---

## 9. Một lỗi thật tìm được nhờ Kubernetes

Khi chạy bài tập 8.5 lần đầu, pod web bị `RESTARTS: 1` dù liveness không hỏi database.
Truy nguyên:

```bash
kubectl logs <pod> --previous
```

```
Server đang chạy tại http://localhost:3000
node:events:502
      throw er; // Unhandled 'error' event
error: terminating connection due to administrator command
Emitted 'error' event on BoundPool instance
```

Nguyên nhân: `pg.Pool` giữ sẵn các kết nối rỗi. Khi Postgres tắt, nó đóng các kết nối
này và pool phát sự kiện `'error'`. Node có quy tắc: sự kiện `'error'` **không ai lắng
nghe** thì ném exception và giết tiến trình. Container thoát với `exitCode 1`.

Bản vá trong `backend/db.js`:

```js
pool.on('error', (err) => {
  console.error('Kết nối rỗi tới database gặp lỗi (pool sẽ tự mở lại):', err.message);
});
```

Sau khi vá, chạy lại bài 8.5: `RESTARTS: 0`, log ghi dòng cảnh báo thay vì sập.

> **Điều đáng nói với sinh viên:** lỗi này có sẵn từ bản Docker Compose, nhưng không
> ai thấy vì hiếm khi restart riêng container db. Kubernetes thay pod liên tục
> (rolling update, dời node, scale) nên phơi bày nó ngay.
>
> Bài học rộng hơn: hạ tầng tốt không *tạo ra* lỗi, nó *phát hiện* lỗi vốn đã ở đó.

---

## 10. Nối vào CI/CD

Các buổi trước đã có pipeline build → test → push image lên GHCR với tag SHA. Bước
cuối chỉ là bảo cluster dùng tag mới:

```bash
kubectl set image deployment/web \
  web=ghcr.io/<user>/dictionary-app-5:${GIT_SHA} \
  -n dictionary

kubectl rollout status deployment/web -n dictionary --timeout=300s
```

`rollout status` trả mã khác 0 nếu pod mới không lên được → pipeline đỏ đúng lúc.

Thêm vào `Jenkinsfile`:

```groovy
stage('Deploy to Kubernetes') {
  steps {
    sh """
      kubectl set image deployment/web web=${IMAGE_TAG} -n dictionary
      kubectl rollout status deployment/web -n dictionary --timeout=300s
    """
  }
}
```

Ba nguyên tắc phải giữ:

1. **Luôn deploy bằng tag SHA**, không bao giờ `:latest`. Không biết đang chạy code
   nào thì không rollback được.
2. **Chờ `rollout status`**, đừng `apply` xong báo thành công ngay.
3. **Hỏng thì `kubectl rollout undo`** — nhanh hơn build lại bản cũ rất nhiều.

> Chuyển `scripts/smoke-test.sh` sang K8s: chạy `kubectl port-forward svc/web 3999:3000 &`
> rồi giữ nguyên toàn bộ phần `check()` — các phép thử không cần đổi.

---

## 11. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `ErrImagePull` / `ImagePullBackOff` | Image chỉ có ở máy, cluster không thấy | `imagePullPolicy: IfNotPresent` + `kind load docker-image` |
| `CrashLoopBackOff` | App chết ngay khi khởi động | `kubectl logs <pod> --previous` |
| `Pending` mãi | Không đủ CPU/RAM, hoặc PVC chưa được cấp | `kubectl describe pod` → xem Events |
| `Init:0/1` không thoát | initContainer chờ db mãi | `kubectl logs <pod> -c wait-for-db` |
| `Running` nhưng `0/1` | readinessProbe hỏng | `kubectl describe pod` → mục Conditions |
| `0/1` + `RESTARTS` tăng dần | livenessProbe hỏng (thường do trỏ nhầm endpoint có hỏi DB) | Tách `/healthz` khỏi `/api/health` |
| `connection refused` khi gõ kubectl | Cluster chưa chạy | `kubectl config current-context` |
| Sửa ConfigMap mà app không đổi | Biến môi trường chỉ nạp lúc pod khởi động | `kubectl rollout restart deployment/web` |
| Xoá StatefulSet mà dữ liệu cũ còn | PVC cố ý không bị xoá theo | `kubectl delete pvc pgdata-db-0` |

---

## 12. Dọn dẹp

```bash
kubectl delete namespace dictionary     # xoá toàn bộ, gồm cả PVC
kind delete cluster --name dictionary   # nếu dùng kind
```

Với Docker Desktop: Settings → Kubernetes → bỏ tick Enable Kubernetes.

---

## 13. Tóm tắt

### Ba điều rút ra

1. **Khai báo thay vì ra lệnh.** Bạn mô tả trạng thái mong muốn, cluster tự giữ cho
   thực tế khớp với nó. Đừng sửa tay trên cluster — sửa YAML rồi `apply`.

2. **Liveness không được phụ thuộc dịch vụ ngoài.** Liveness hỏng thì K8s *giết*
   container. Để nó đi hỏi database là tự tạo ra `CrashLoopBackOff` khi database
   gặp sự cố. Readiness mới là chỗ kiểm tra phụ thuộc.

3. **Ứng dụng không cần biết nó chạy ở đâu.** `DB_HOST=db` chạy đúng trên cả Compose
   lẫn Kubernetes. Cấu hình đi từ ngoài vào qua ConfigMap/Secret; image giữ nguyên
   ở mọi môi trường.

### Đối chiếu công cụ

| | Docker Compose | Kubernetes |
|---|---|---|
| Phạm vi | một máy | nhiều máy |
| Khi container chết | restart tại chỗ | lên lịch lại, có thể sang node khác |
| Scale | sửa file, chạy lại | `kubectl scale`, hoặc HPA tự động |
| Cập nhật | dừng cũ, dựng mới (có downtime) | rolling update (không downtime) |
| Rollback | tự làm tay | `kubectl rollout undo` |
| Độ phức tạp | thấp | cao |
| Hợp với | phát triển ở máy, ứng dụng nhỏ | production nhiều dịch vụ |

> Kubernetes **không thay thế** Docker Compose. Compose vẫn là công cụ tốt nhất để
> chạy ở máy cá nhân. Hai thứ dùng chung một image, phục vụ hai mục đích khác nhau.
