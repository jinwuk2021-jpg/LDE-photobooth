# Cắm máy ảnh Sony a6300 vào iPad: việc cần làm

Mục tiêu: a6300 chụp ảnh cho khách (đẹp hơn camera iPad), iPad điều khiển máy ảnh qua cáp USB.
Màn chụp hiện hình từ máy ảnh, nên khách thấy đúng khung sẽ in. Clip Live vẫn quay bằng camera trước của iPad.
Nếu máy ảnh lỗi ở tấm nào (rớt cáp, không lấy được nét…), tấm đó tự dùng ảnh của camera iPad, khách không bị kẹt.

## 0. Mang theo

- [ ] a6300 + ống kính (nên dùng ống zoom góc rộng, ví dụ 16–50 mm)
- [ ] **Pin giả AC-PW20** (cắm điện thẳng cho máy ảnh). Một viên pin thường chỉ chụp được vài trăm tấm và tắt giữa sự kiện
- [ ] **Cáp Micro‑USB → USB‑C có truyền dữ liệu** (cáp chỉ để sạc thì iPad không thấy máy ảnh). Thử trước ở nhà
- [ ] Nếu cần vừa sạc iPad vừa cắm máy ảnh: **hub USB‑C có cổng sạc PD**
- [ ] Chân máy hoặc ngàm để gắn a6300 **ngay trên iPad**, ống kính sát camera trước của iPad nhất có thể
- [ ] Thẻ nhớ trong máy (không bắt buộc, xem mục 1)

## 1. Cài đặt trên a6300 (menu tiếng Anh)

- [ ] Setup → **USB Connection: PC Remote** (quan trọng nhất; không có thì app báo "Máy ảnh không vào chế độ điều khiển")
- [ ] Camera → **File Format: JPEG** (không để RAW hay RAW+JPEG)
- [ ] Camera → **Image Size: S** (hoặc M). Ảnh in chỉ cần khoảng 1600 px, ảnh nhỏ truyền qua cáp nhanh hơn
- [ ] Camera → Aspect Ratio: **3:2**
- [ ] Camera → **Priority Set in AF‑S: Release** (chưa lấy nét xong vẫn chụp, không bị kẹt)
- [ ] Focus Mode: AF‑S, Focus Area: Wide, **Face Detection: On**
- [ ] Setup → **Power Save Start Time: 30 Min**, Auto Pow. OFF Temp.: High
- [ ] Custom → **Release w/o Card: Enable** (không có thẻ vẫn chụp được)
- [ ] Custom → **Live View Display: Setting Effect ON** (hình trên iPad sáng tối đúng như ảnh)
- [ ] Chế độ chụp: **M** hoặc **A** với ánh sáng cố định của booth. Đèn flash của máy ảnh làm khách loá, nên dùng đèn liên tục
- [ ] Tắt tiếng bíp nếu muốn: Setup → Audio signals: Off

## 2. Kết nối

- [ ] Bật a6300, cắm cáp vào iPad. Lần đầu iPad hỏi quyền truy cập máy ảnh: bấm **Cho phép**
- [ ] Mở admin (giữ nút bánh răng ⚙ góc trên bên phải màn chờ 3 giây) → trang **Máy ảnh**
  - [ ] **Chụp bằng máy ảnh Sony** đang bật (bật sẵn)
  - [ ] Nhãn xanh **Sẵn sàng**, tên máy **ILCE‑6300**
  - [ ] Thẻ **Xem trước** có hình chuyển động
  - [ ] Bấm **Chụp thử** → hiện ảnh và thời gian (ghi lại thời gian, mong đợi dưới 2 giây)
- [ ] Góc màn chờ hiện **máy ảnh ok**
- [ ] Không kết nối được: tháo cáp, tắt rồi bật máy ảnh, cắm lại; hoặc bấm **Kết nối lại** trong admin

## 3. Thử một lượt thật

- [ ] Màn chờ → chọn khung → màn chụp hiện hình **từ máy ảnh** (góc nhìn của ống kính a6300)
- [ ] Mỗi lần đếm ngược về 0, máy ảnh bấm chụp (nghe tiếng màn trập)
- [ ] Màn chọn ảnh có ảnh từ máy ảnh (nét, màu đẹp hơn rõ so với camera iPad)
- [ ] In, rồi quét QR: ảnh và clip đều có
- [ ] Admin → Máy ảnh → Kiểm tra nhanh: **Ảnh phải dùng camera iPad: 0 / X**

## 4. Thử lỗi

- [ ] **Rút cáp giữa lúc chụp** → lượt chụp vẫn chạy hết (tấm đó dùng camera iPad), màn chụp quay về hình iPad
- [ ] Cắm lại cáp → admin quay về chấm xanh (nếu không: **Kết nối lại**)
- [ ] Che ống kính / để tối hẳn → máy ảnh vẫn chụp (nhờ Priority Set in AF‑S: Release)
- [ ] Để máy ảnh không dùng 15 phút rồi chụp → vẫn chụp được (Power Save 30 Min)

## 5. Gửi lại cho Claude

- Ảnh chụp màn hình trang **Máy ảnh** trong admin (thẻ **Nhật ký kết nối**)
- Thời gian **Chụp thử**
- Có vấn đề gì ở mục 3 và 4

## Ghi chú kỹ thuật

- Kết nối kiểu "PC Remote" của Sony qua PTP (giống libgphoto2): iPad gửi lệnh qua ImageCaptureCore
  (`ios/Runner/AppDelegate.swift`, `BoothPtp`), còn giao thức Sony viết bằng Dart (`lib/camera/sony_camera.dart`, có unit test).
- Chụp: nhấn nửa (0xD2C1) → nhấn hết (0xD2C2) → nhả, chờ ảnh vào bộ nhớ máy (0xD215) rồi tải ảnh 0xFFFFC001.
  Xem trước: ảnh 0xFFFFC002, khoảng 10–20 hình mỗi giây.
- Chưa thử với máy thật: lần đầu cắm a6300, nếu không kết nối được, gửi nhật ký trong admin để Claude sửa.
