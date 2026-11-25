# Photobooth

App photobooth cho một sự kiện, chạy trên iPad Pro 11" (M4), xoay ngang, in ra Canon SELPHY CP1500.
Dùng lại từ Lensly: camera và clip Live (`packages/film_camera`, live recorder, ring buffer), chuỗi chụp tự động,
6 filter, làm mịn da, bảng màu và font, cùng máy chủ chia sẻ (Worker `lenslycam.com`, trang `/b/<id>`).

Luồng: màn chờ → chọn khung (các khung đang bật trong admin) → chụp (số ô + 2 tấm: 2 Cut chụp 4, 3 Cut chụp 5, 4 Cut chụp 6, 6 Cut chụp 8) → chọn ảnh và filter trong thời gian giới hạn (mặc định 45 giây, chỉnh trong admin; hết giờ tự chọn đủ và in) → In → màn cảm ơn có QR. QR chỉ được tạo khi bấm In và in ở vị trí cố định của từng khung. 4 Cut là khổ ngang, khi in được xoay sẵn cho vừa giấy dọc.

## Build (chỉ cài lên iPad của mình, không lên App Store)

Chuẩn bị một lần:

1. Trong repo Lensly, deploy Worker có phần booth (xem `server/share-worker/README.md`, mục "Photobooth sự kiện"):
   ```sh
   cd ~/Vintage-Came/server/share-worker
   npx wrangler secret put BOOTH_KEY     # chuỗi ngẫu nhiên: openssl rand -hex 24
   npx wrangler deploy
   ```
   Trên Cloudflare, bucket `fct-clips` → Lifecycle rules → thêm prefix `booth/` → xoá sau 30 ngày.
2. `cp booth_defines.example.json booth_defines.json` rồi dán `BOOTH_KEY` vào file đó (file này không đưa lên git).
3. Mở `ios/Runner.xcworkspace` bằng Xcode → Runner → Signing & Capabilities → chọn Team (Apple ID cá nhân cũng được).

Cài lên iPad (cắm cáp, bật Developer Mode trên iPad):

```sh
flutter pub get
flutter run --release --dart-define-from-file=booth_defines.json
```

Nếu dùng Apple ID miễn phí, app hết hạn sau 7 ngày. Nhớ cài lại sát ngày sự kiện.

Ảnh của mỗi lượt khách nằm trong app Tệp → Trên iPad → Photobooth → `Booth/<ngày>/<giờ>/`
(`print.jpg`, `1–4.jpg`, `1–4.mp4`, `link.txt`), nên không mất ảnh khi upload lỗi.

Màn admin: giữ ngón tay ở góc trên bên phải màn chờ 3 giây (không có PIN, không có gì hiện ra ở góc đó).

Khung in: 8 khung có sẵn (2 / 3 / 4 / 6 Cut, mỗi loại nền ngà và nền đen). Vị trí ô ảnh và QR nằm trong
`assets/frames/<id>/frame.json` (lấy từ gói thiết kế); phần trang trí, tiêu đề, dòng ngày và dòng "Quét mã…" vẽ bằng code
nên luôn theo nội dung nhập trong admin và ngôn ngữ khách chọn. Mặc định bật 2 Cut ngà, 3 Cut ngà, 4 Cut đen, 6 Cut ngà;
bật / tắt trong admin → **Khung ảnh** (luôn còn ít nhất 1 khung).

## Checklist trước sự kiện

1. Bật điểm phát cá nhân trên iPhone, bật **Tối đa hoá tương thích** (2.4GHz). SELPHY và iPad cùng vào mạng đó.
2. Mở admin → bật **In ảnh cho khách** → **Chọn máy in** → **In thử** từng khung. Làm theo [docs/SELPHY_TODO.md](docs/SELPHY_TODO.md).
3. Chụp thử một lượt. Quét QR bằng điện thoại có cài Lensly và một điện thoại không cài: phải xem được ảnh in, 4 ảnh,
   4 clip, và tải về được. Ở góc màn chờ phải hiện "đã lên hết".
4. Vào admin sửa **tiêu đề** và **dòng ngày**. Chọn mức **làm mịn da**.
5. Bật **Guided Access**: Cài đặt → Trợ năng → Truy cập được hướng dẫn. Mở app, bấm nút sườn 3 lần để bắt đầu.
6. Cắm sạc cho iPad. Màn hình không tự khoá khi app đang mở.

## Chạy test

```sh
flutter test                                             # app
cd ~/Vintage-Came/server/share-worker && npm test        # Worker
```
