{{flutter_js}}
{{flutter_build_config}}

// Không dùng Flutter service worker trong chế độ LAN để Safari luôn nhận bản
// mới sau mỗi lần build, thay vì giữ giao diện cũ trong cache.
_flutter.loader.load();
