# Kiến trúc Action Planner AI

Tài liệu này giúp người mới xác định nhanh nơi cần sửa khi phát triển demo.

## Luồng chính

```text
Flutter UI
   ↓
AppState (trạng thái và nghiệp vụ phía client)
   ↓
TaskRepository / REST client
   ↓ HTTP + JWT
Express API
   ├─ MongoDB (user, task, cấu hình, phản hồi, thống kê)
   ├─ Ollama / OpenAI / Gemini / Anthropic
   └─ TTS trên thiết bị / vietTTS / VietVoice-TTS
```

## Flutter

- `lib/main.dart`: khởi tạo ứng dụng, theme và `AppState`.
- `lib/state/app_state.dart`: phiên đăng nhập, dữ liệu công việc, lịch và các
  thao tác bất đồng bộ dùng chung giữa các màn hình.
- `lib/data/task_repository.dart`: hợp đồng dữ liệu, mock repository và REST
  client. URL backend nhận qua `API_BASE_URL`.
- `lib/models/`: model công việc và lịch trình, gồm chuyển đổi JSON.
- `lib/ui/`: đăng nhập, trang chủ, trình sửa công việc, cấu hình AI/giọng đọc,
  phản hồi và dashboard quản trị.
- `lib/services/`: thông báo deadline; dùng implementation phù hợp với nền
  tảng thông qua conditional import.

Khi thêm một trường cho công việc, cập nhật theo thứ tự: model → JSON trong
repository → API/MongoDB → `AppState` → UI → test round-trip.

## Backend

- `backend/src/server.js`: REST API, xác thực JWT, CRUD, AI, thống kê và quản
  trị. Mỗi truy vấn dữ liệu người dùng phải luôn kèm `userId` lấy từ JWT.
- `backend/src/voice.js`: adapter tổng hợp giọng nói và cache WAV. Đây là điểm
  thay thế engine TTS mà không cần sửa UI.
- `backend/.env.example`: danh sách cấu hình được phép public. Không commit
  `backend/.env` hoặc API key thật.

Các nhóm endpoint chính:

- `/api/auth/*`: đăng ký, đăng nhập và phiên người dùng.
- `/api/tasks/*`: công việc, bước nhỏ và tiến độ.
- `/api/schedule/*`: tạo và áp dụng lịch trong ngày.
- `/api/ai/*`: chat, phân tích và kiểm tra cấu hình nhà cung cấp AI.
- `/api/settings/*`: cấu hình AI, thông báo và giọng đọc theo tài khoản.
- `/api/admin/*`: dashboard, cấu hình mặc định và xử lý phản hồi.

## Nguyên tắc mở rộng

1. Không đặt secret trong Dart, APK, URL hoặc Git; mọi khóa dịch vụ đi qua
   backend và biến môi trường.
2. Mọi endpoint mới phải xác thực quyền sở hữu dữ liệu, không nhận `userId`
   trực tiếp từ client.
3. Giữ AI và TTS là tùy chọn: CRUD công việc vẫn phải hoạt động khi dịch vụ
   ngoài chưa được cấu hình.
4. Chạy `npm run check`, `dart format`, `flutter analyze` và `flutter test`
   trước khi tạo pull request.
5. Với thay đổi database có dữ liệu production, bổ sung migration thay vì chỉ
   dựa vào giá trị mặc định trong code.

## Giới hạn hiện tại của demo

- Backend đang tập trung trong một file lớn; khi thêm nhiều domain nên tách
  router, service, validation và data-access theo từng module.
- Access token có hạn 7 ngày nhưng chưa có refresh-token rotation.
- Chưa có integration test cho REST API và MongoDB.
- HTTP nội bộ và CORS mở phù hợp cho phát triển; triển khai thật cần HTTPS,
  origin allowlist, rate limit, security headers và quản lý secret tập trung.
