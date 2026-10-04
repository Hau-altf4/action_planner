# Action Planner AI

Ứng dụng Android bằng Flutter/Dart để quản lý công việc, theo dõi tiến độ,
lập lịch trong ngày và nhận gợi ý từ AI. Ứng dụng mặc định kết nối REST API
thật để mỗi tài khoản dùng dữ liệu riêng được lưu trong MongoDB.

## Chức năng đã có

- Đăng ký, đăng nhập và đăng xuất.
- Tạo, chỉnh sửa, xem chi tiết và lọc công việc theo trạng thái.
- Ưu tiên, danh mục, thời lượng dự kiến, deadline và các bước nhỏ.
- Cập nhật trạng thái, tiến độ và hoàn thành từng bước.
- Dashboard và lịch trình trong ngày.
- Tạo lại lịch theo độ ưu tiên và deadline.
- Màn hình chat với trợ lý AI.
- REST client, JWT backend, MongoDB và OpenAI Responses API.
- AI đa nhà cung cấp: Ollama, OpenAI, Google Gemini và Anthropic Claude.
- API key riêng theo user, được mã hóa ở backend; admin quản lý AI mặc định.
- Thông báo native trước deadline 10 phút và khi quá hạn.
- Dashboard admin: user, mức sử dụng, độ trễ AI, đánh giá và khiếu nại.
- Khôi phục phiên đăng nhập an toàn và cache công việc để mở app nhanh hơn.

## 1. Chạy ứng dụng

```powershell
flutter pub get
flutter run
```

Khi chạy trên Android Emulator, ứng dụng mặc định kết nối backend tại
`http://10.0.2.2:3000`. Khi chạy trên Windows, địa chỉ mặc định là
`http://127.0.0.1:3000`. Hãy khởi động backend trước khi đăng ký hoặc đăng nhập.

Chỉ dùng dữ liệu tạm trong bộ nhớ khi chủ động chạy:

```powershell
flutter run --dart-define=USE_MOCK_DATA=true
```

## 2. Khởi tạo MongoDB

1. Cài MongoDB Community Server và bảo đảm service `MongoDB` đang chạy.
2. Backend mặc định kết nối tới
   `mongodb://127.0.0.1:27017/action_planner`.
3. Không cần tạo collection thủ công. Backend tự tạo database, collection và
   index cần thiết khi khởi động lần đầu.

## 3. Chạy backend Node.js

Yêu cầu Node.js 20 trở lên.

```powershell
cd backend
Copy-Item .env.example .env
npm install
npm run dev
```

Hoặc từ thư mục gốc, chạy launcher sau. Script sẽ kiểm tra cổng `3000` và mở
backend ở chế độ ẩn nếu server chưa chạy:

```powershell
.\start_backend.ps1
```

Launcher chờ tối đa 60 giây cho MongoDB/backend sẵn sàng. Nếu khởi động lỗi,
chi tiết được ghi trong `backend/logs/*.err.log` thay vì chỉ hiện thông báo
“không kết nối được”. Sau khi khởi động, kiểm tra nhanh bằng:

```powershell
Invoke-RestMethod http://127.0.0.1:3000/health
```

Mở `.env` và kiểm tra `MONGODB_URI`, `MONGODB_DB`, `JWT_SECRET`. Kiểm tra kết
nối:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

Kết quả đúng chứa
`{ status: "ok", database: "connected", databaseName: "action_planner" }`.

### Tạo tài khoản quản trị

Đặt các biến sau trong `backend/.env`, sau đó khởi động lại backend:

```env
API_KEY_ENCRYPTION_SECRET=mot-chuoi-rieng-dai-va-ngau-nhien
ADMIN_EMAIL=email-cua-ban@example.com
ADMIN_PASSWORD=mat-khau-admin-it-nhat-12-ky-tu
ADMIN_NAME=Quản trị viên
```

`backend/.env.example` chỉ là file mẫu và backend **không đọc file này**. Không
đặt dấu `\` trước `@` trong email. Ví dụ đúng là `admin@gmail.com`. Mật khẩu
`123456` chỉ phù hợp để thử trong LAN; hãy đổi sang mật khẩu dài, riêng biệt
trước khi triển khai.

Nếu email đã đăng ký, backend tự nâng tài khoản đó thành admin. Nếu chưa tồn
tại, backend tự tạo tài khoản khi `ADMIN_EMAIL` và `ADMIN_PASSWORD` đều có giá
trị. Đăng nhập lại để JWT mới nhận role admin. Không commit file `.env`.

## 4. AI local miễn phí với Ollama

Project mặc định dùng Ollama trên máy nên không cần API key và không phát sinh
phí theo lượt sử dụng.

1. Cài Ollama for Windows từ `https://ollama.com/download/windows`.
2. Tải model dùng cho project:

   ```powershell
   ollama pull qwen3:1.7b
   ```

3. Kiểm tra `backend/.env`:

   ```env
   AI_PROVIDER=ollama
   OLLAMA_BASE_URL=http://127.0.0.1:11434
   OLLAMA_MODEL=qwen3:1.7b
   ```

4. Khởi động lại backend và kiểm tra `/health`. Kết quả phải chứa
   `"aiProvider": "ollama"`.

Để Ollama phản hồi nhanh hơn, cấu hình mặc định của project giữ model trong RAM
30 phút, dùng context 2048 token, giới hạn câu trả lời và tự chọn số CPU thread:

```env
OLLAMA_KEEP_ALIVE=30m
OLLAMA_NUM_CTX=2048
OLLAMA_NUM_THREAD=
```

Sau khi mở Ollama, làm nóng model một lần:

```powershell
ollama run qwen3:1.7b "Trả lời OK"
```

Nếu máy chỉ có 8 GB RAM, tiếp tục dùng `qwen3:1.7b`. Nếu có GPU/RAM tốt hơn,
có thể chọn model lớn hơn trong dashboard admin. Không chạy đồng thời nhiều
model vì Ollama sẽ phải nạp/đẩy model khỏi RAM và làm tăng độ trễ.

Chat nhận ngữ cảnh công việc của người đang đăng nhập. Phân tích task và đề
xuất lịch sử dụng JSON schema. Một phương án lịch chỉ được lưu sau khi người
dùng chọn **Áp dụng**; nếu chọn **Chưa hợp lý**, người dùng có thể nhập phản hồi
để AI tạo phương án mới.

Muốn quay lại OpenAI API, đặt `AI_PROVIDER=openai`, điền `OPENAI_API_KEY` và
chọn `OPENAI_MODEL`. Không đặt khóa API trong Dart, `--dart-define`, APK, Git
hoặc mã nguồn public.

Người dùng cũng có thể vào **Cá nhân → Cài đặt AI**, bật **Dùng AI riêng của
tôi**, chọn Ollama/OpenAI/Gemini/Claude, nhập model và API key rồi bấm **Lưu và
kiểm tra kết nối**. Khóa chỉ được gửi qua backend, mã hóa AES-256-GCM trong
MongoDB và không bao giờ được trả lại cho app. Production bắt buộc dùng HTTPS.

Admin vào **Cá nhân → Dashboard quản trị → Cấu hình AI mặc định** để chọn AI
cho tất cả user không có cấu hình riêng.

## 5. Kết nối Flutter với backend

Android Emulator truy cập máy phát triển qua địa chỉ `10.0.2.2`:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Với điện thoại thật, thay bằng IPv4 LAN của máy tính, ví dụ:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000
```

Điện thoại và máy tính phải cùng mạng; cho phép cổng 3000 qua Windows Firewall.
`usesCleartextTraffic` đang bật để phát triển qua HTTP nội bộ. Trước khi phát
hành, triển khai backend bằng HTTPS rồi đặt thuộc tính này thành `false`.

## 6. Thông báo deadline

Vào **Cá nhân → Bật thông báo deadline** và cấp quyền. App tạo hai thông báo
native cho mỗi task chưa hoàn thành:

- Trước deadline 10 phút.
- Sau deadline 1 phút, nếu task chưa được đánh dấu hoàn thành.

Android dùng channel riêng **Nhắc deadline**, có rung, âm thanh và mức ưu tiên
cao. Có thể đổi riêng âm thanh của channel này tại **Cài đặt → Ứng dụng →
Action Planner AI → Thông báo → Nhắc deadline → Âm thanh**. iOS dùng âm báo hệ
thống với mức Time Sensitive. Khi hoàn thành task, hai lịch thông báo được hủy.

## 7. Chạy trên iPhone thật

Có thể chạy trên iPhone thật, không bắt buộc Android. Tuy nhiên Apple yêu cầu
build và ký ứng dụng bằng **macOS + Xcode**; Windows không thể cài bản Flutter
iOS trực tiếp chỉ bằng cáp USB.

1. Chép/clone project sang máy Mac, cài Xcode và Flutter, rồi chạy:

   ```bash
   flutter doctor
   flutter pub get
   open ios/Runner.xcworkspace
   ```

2. Trong Xcode, vào **Settings → Accounts**, đăng nhập Apple ID.
3. Cắm iPhone vào Mac, mở khóa, chọn **Trust This Computer**.
4. Trên iPhone bật **Settings → Privacy & Security → Developer Mode**, khởi
   động lại máy và xác nhận.
5. Trong Xcode chọn target **Runner → Signing & Capabilities**, bật
   **Automatically manage signing**, chọn Personal Team và đổi Bundle
   Identifier `com.example.action_planner` thành một giá trị duy nhất, ví dụ
   `com.tenban.actionplanner`.
6. Bảo đảm Mac và iPhone cùng Wi-Fi. Backend vẫn chạy trên máy phát triển và
   phải lắng nghe LAN. Lấy IPv4 của Mac rồi chạy:

   ```bash
   flutter devices
   flutter run -d <iphone-device-id> \
     --dart-define=API_BASE_URL=http://192.168.1.10:3000
   ```

7. Nếu iOS chặn HTTP nội bộ, dùng HTTPS cho backend (khuyến nghị) hoặc chỉ cho
   phép local-network/ATS trong bản debug. Không mở ngoại lệ HTTP rộng khi phát
   hành production.

Apple ID miễn phí dùng được để test trên máy cá nhân nhưng provisioning profile
hết hạn định kỳ (thường 7 ngày), khi đó cần build/cài lại. Để phát hành qua
TestFlight/App Store cần Apple Developer Program trả phí.

### Dùng iPhone như ứng dụng web từ Windows (không cần Mac)

Máy Windows và iPhone phải cùng Wi-Fi. Từ thư mục project, chạy:

```powershell
.\start_web.ps1
```

Sau khi sửa mã Flutter, build lại trước khi phục vụ:

```powershell
.\start_web.ps1 -Rebuild
```

Script tự khởi động backend, phục vụ bản web release ở cổng `8080` và in URL
LAN, ví dụ:

```text
On iPhone: http://192.168.88.166:8080
```

Mở URL đó bằng Safari. Để có biểu tượng giống một ứng dụng, chọn **Share → Add
to Home Screen → Add**. Bản web tự gọi backend tại cùng IP ở cổng `3000`, nên
không cần sửa `API_BASE_URL` khi IP Wi-Fi thay đổi.

Nếu Safari không mở được, chọn **Allow access** trong hộp thoại Windows Firewall
cho mạng Private, hoặc mở PowerShell bằng quyền Administrator và tạo rule chỉ
cho mạng Private:

```powershell
New-NetFirewallRule -DisplayName "Action Planner Web (Private LAN)" `
  -Direction Inbound -Action Allow -Protocol TCP `
  -LocalPort 3000,8080 -Profile Private
```

Không chọn profile Public. HTTP LAN phù hợp để thử trong mạng tin cậy, nhưng
không nên mở các cổng này ra Internet. Trên bản web HTTP, app có thể nhắc bằng
notification trình duyệt hoặc hộp thoại khi trang vẫn đang mở. Nếu Safari đã bị
đóng/đưa ra khỏi bộ nhớ, thông báo nền cần HTTPS + Web Push hoặc bản native.

## 8. Kiểm tra và build APK

```powershell
dart format lib test
flutter analyze
flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

APK release nằm trong `build/app/outputs/flutter-apk/app-release.apk`.

## Cấu trúc chính

```text
lib/
  data/task_repository.dart   # Mock repository và REST client
  models/                     # Task, step và lịch trình
  state/app_state.dart        # Trạng thái và business logic
  ui/                         # Đăng nhập, dashboard, task, lịch, AI, hồ sơ
backend/
  src/server.js               # Express API, JWT, MongoDB, OpenAI
  .env.example                # Mẫu cấu hình không chứa bí mật
```

## Trước khi đưa lên production

- Lưu JWT bằng Android Keystore/secure storage và hỗ trợ refresh token.
- Bổ sung refresh token xoay vòng; access token hiện được lưu bằng Keychain/
  Keystore nhưng vẫn có hạn 7 ngày.
- Thêm rate limit, Helmet, validation schema, logging và migration database.
- Dùng HTTPS, Secret Manager và tài khoản MongoDB quyền tối thiểu.
- Thêm xóa task, conflict resolution hai chiều và phân trang cho dữ liệu lớn.
- Viết integration test cho API và kiểm thử trên nhiều kích thước màn hình.
