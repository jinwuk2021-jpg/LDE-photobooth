# Photobooth

App photobooth cho một sự kiện, chạy trên iPad Pro 11" (M4), xoay ngang, in ra Canon SELPHY CP1500.
Dùng lại từ Lensly: camera và clip Live (`packages/film_camera`, live recorder, ring buffer), chuỗi chụp tự động,
6 filter, làm mịn da, bảng màu và font, cùng máy chủ chia sẻ (Worker `lenslycam.com`, trang `/b/<id>`).

Luồng: màn chờ → chọn khung (8 Cut, 2 Cut, 3 Cut, 4 Cut, 6 Cut như menu) → chụp (số ô + 2 tấm, ít nhất 6) → chọn ảnh và filter trong thời gian giới hạn (mặc định 60 giây, chỉnh trong admin; hết giờ tự chọn đủ và in) → In → màn cảm ơn có QR. QR chỉ được tạo khi bấm In và in ở vị trí cố định của từng khung. 4 Cut là khổ ngang, khi in được xoay sẵn cho vừa giấy dọc.

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

Màn admin: chạm 5 lần vào góc trên bên phải màn chờ, nhập PIN `1234`.

## Checklist trước sự kiện

1. Bật điểm phát cá nhân trên iPhone, bật **Tối đa hoá tương thích** (2.4GHz). SELPHY và iPad cùng vào mạng đó.
2. Mở admin → **Chọn máy in** → **In thử**. Kiểm tra khổ ảnh, viền, đường cắt ở giữa; QR quét được.
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
