# Kết nối Canon SELPHY CP1500: việc cần làm

Mục tiêu: iPad in thẳng sang SELPHY qua AirPrint, không hiện hộp thoại, đúng khổ postcard 100×148 mm.
Trong app, phần in đang **tắt** sẵn. Bật bằng công tắc trong admin, không cần build lại app.

## 0. Mang theo

- [ ] SELPHY CP1500 + dây nguồn
- [ ] Bộ giấy và mực **cỡ Postcard** (KP-108IN: 108 tờ + 3 hộp mực, mỗi hộp mực đủ 36 tờ)
- [ ] Khay giấy cỡ Postcard (khay đi kèm máy)
- [ ] iPad đã cài bản app mới nhất (Claude cài khi iPad cắm cáp vào Mac)
- [ ] iPhone làm điểm phát (hotspot)

## 1. Đưa SELPHY vào chung mạng với iPad

- [ ] iPhone: Cài đặt → Điểm truy cập cá nhân → bật **Tối đa hoá tương thích** (để phát sóng 2.4 GHz)
- [ ] SELPHY: Menu → Cài đặt Wi‑Fi → Kết nối Wi‑Fi → chọn tên hotspot của iPhone → nhập mật khẩu
  (**không** dùng chế độ "Kết nối trực tiếp", vì iPad sẽ mất internet và không upload được)
- [ ] iPad vào cùng hotspot đó
- [ ] Thử ngoài app trước: mở app Ảnh trên iPad → chọn 1 ảnh → Chia sẻ → In → xem SELPHY có hiện trong danh sách và in được không
  - Không thấy máy in: tắt/bật lại SELPHY, kiểm tra iPhone và SELPHY cùng mạng, thử tắt rồi bật lại hotspot

## 2. Cài đặt trong app

Mở admin: chạm 5 lần vào góc trên bên phải màn chờ, nhập PIN `1234`.

- [ ] Bật **In ảnh cho khách**
- [ ] **Chọn máy in** → chọn SELPHY
  (nếu iPad hỏi quyền "Mạng cục bộ" thì bấm **Cho phép**)
- [ ] **Kiểm tra kết nối** → phải báo "Máy in trả lời: OK"

## 3. In thử từng khung (ghi lại kết quả)

Bấm lần lượt **In thử 2 Cut**, **3 Cut**, **4 Cut**, **6 Cut** trong admin.

| Kiểm tra | 2 Cut | 3 Cut | 4 Cut | 6 Cut |
|---|---|---|---|---|
| In ra mà **không** hiện hộp thoại nào trên iPad | | | | |
| Đúng khổ postcard, không bị thu nhỏ hay chừa lề trắng lạ | | | | |
| Có viền trắng hay tràn lề (ghi lại) | | | | |
| Mép bị cắt bao nhiêu (đường khung mảnh sát mép bị cắt cũng không sao) | | | | |
| QR và chữ còn nguyên, không bị cắt | | | | |
| **4 Cut** nằm đúng chiều, không bị xoay 2 lần | – | – | | – |
| Màu vàng in ra có đẹp không (in nhiệt hay ra tối) | | | | |
| Dùng điện thoại quét QR trên tấm in → mở được trang | | | | |

Tấm in thử có QR trỏ tới một link giả (`.../b/testtesttest`): trang sẽ báo "đang tải lên", như vậy là bình thường.

## 4. Thử hàng đợi và lỗi

- [ ] Bấm In thử 3 lần liên tiếp thật nhanh → máy in ra đủ 3 tấm lần lượt, không mất tấm nào
- [ ] Đo thời gian in một tấm (CP1500 khoảng 40–45 giây mỗi tấm postcard)
- [ ] **Tắt SELPHY** rồi bấm In thử → trong "Hàng đợi in" lệnh phải chuyển sang **Lỗi** → bật máy lại → bấm **In lại** → in được
- [ ] **Rút khay giấy** (giả hết giấy) rồi bấm In thử → ghi lại chuyện gì xảy ra:
  - báo Lỗi ngay, hay
  - đứng chờ (app tự bỏ qua sau tối đa **3 phút** rồi báo "Máy in không phản hồi sau 3 phút")
- [ ] Lắp lại giấy → In lại lệnh lỗi

## 5. Chạy thử một lượt thật

- [ ] Màn chờ → chọn khung → chụp → chọn ảnh → **In** → màn "Đang in!" hiện QR
- [ ] Máy in ra đúng tấm đó, QR trên giấy mở đúng trang ảnh và video
- [ ] Góc màn chờ hiện "máy in ok"

## 6. Gửi lại cho Claude

- Ảnh chụp các tấm in thử (thấy rõ mép, viền, màu, QR)
- Bảng ở mục 3 đã điền
- Ảnh chụp màn hình "Hàng đợi in" nếu có lỗi (kèm dòng lỗi)
- Thời gian in một tấm, và kết quả thử rút khay giấy

Dựa vào đó Claude có thể chỉnh:
- lề an toàn hoặc tỉ lệ tấm in nếu bị cắt mép hay có viền trắng
- chiều xoay của 4 Cut
- độ sáng và màu vàng nếu in ra tối
- thời gian chờ lỗi hoặc cách báo lỗi cho nhân viên

## Ghi chú kỹ thuật

- App gửi lệnh in qua `UIPrintInteractionController` tới máy in đã chọn (`UIPrinter(url:)`), loại ảnh `.photo`, khổ dọc,
  khổ giấy 283.5 × 419.5 pt (100×148 mm). Lệnh in đi lần lượt từng cái: lệnh sau chỉ gửi khi lệnh trước đã báo xong
  hoặc đã quá 3 phút.
- File gửi máy in: `Booth/<ngày>/<giờ>/print.jpg` (4 Cut dùng `print_may_in.jpg`, đã xoay dọc). In thử nằm trong `Booth/in-thu/`.
- Code: `ios/Runner/AppDelegate.swift` (phần native), `lib/services/printer.dart` (hàng đợi in).
