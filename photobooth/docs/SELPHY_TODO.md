# Kết nối Canon SELPHY CP1500: việc cần làm

Mục tiêu: iPad in thẳng sang SELPHY qua AirPrint, không hiện hộp thoại, đúng khổ postcard 100×148 mm.
Trong app, phần in đã **bật sẵn**: chỉ cần chọn máy in là in được. Mọi tuỳ chọn in đều chỉnh trong admin,
không cần build lại app.

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
- [ ] SELPHY: Cài đặt → Cài đặt máy in → **Tiết kiệm điện (Power Saving): Tắt**. Mặc định máy tự tắt sau ~5 phút
  không dùng, đây là lý do hay gặp nhất khiến app "mất" máy in giữa sự kiện. (Tên mục có thể khác chút tuỳ ngôn ngữ máy.)
- [ ] Cắm SELPHY vào nguồn điện, không chạy pin
- [ ] iPhone làm hotspot: cắm sạc, để màn hình sáng hoặc ở trang Điểm truy cập cá nhân (hotspot ít bị ngắt hơn)
- [ ] iPad vào cùng hotspot đó
- [ ] Thử ngoài app trước: mở app Ảnh trên iPad → chọn 1 ảnh → Chia sẻ → In → xem SELPHY có hiện trong danh sách và in được không
  - Không thấy máy in: tắt/bật lại SELPHY, kiểm tra iPhone và SELPHY cùng mạng, thử tắt rồi bật lại hotspot

## 2. Cài đặt trong app

Mở admin: giữ nút bánh răng ⚙ ở góc trên bên phải màn chờ 3 giây (vòng vàng chạy đầy).

- [ ] Trang **Máy in** → thẻ **Khi in**: **Tự in khi khách bấm In** đang bật (bật sẵn)
- [ ] **Tìm máy in AirPrint** (hoặc **Chọn máy khác**) → chọn SELPHY. Không thấy máy thì nhập IP ở thẻ **Kết nối thủ công bằng IP**
  (nếu iPad hỏi quyền "Mạng cục bộ" thì bấm **Cho phép**)
- [ ] Góc trên bên phải trang hiện nhãn xanh **Sẵn sàng**; thẻ **Kiểm tra nhanh**: **Máy in phản hồi** có số ms
- [ ] Thanh bên trái: chấm xanh cạnh **Máy in**

App tự giữ kết nối: hỏi máy in mỗi 15 giây khi không thấy (mỗi 60 giây khi đang ổn), và hỏi lại ngay khi mở
lại app. Nếu máy in mất kết nối lúc khách bấm in, tấm đó **không bị mất**: nằm chờ ("Đang chờ máy in kết nối lại")
và tự in khi máy in có lại, **nếu chờ chưa quá 15 phút**. Tấm chờ lâu hơn (vd. in thử lúc máy in tắt, hay từ hôm trước)
không tự in nữa, để bật máy in lên không ra tấm thừa; nó hiện "Chưa in" trong **Lịch sử in**, cần thì bấm **In lại**.
Tấm đã gửi sang máy in mà iOS báo lỗi (hết giấy, kẹt giấy…) **không tự gửi lại** (có khi tờ đó vẫn ra, gửi lại là in
đôi): app báo **Lỗi** trong **Lịch sử in**; kiểm tra khay giấy, tấm chưa ra thật thì bấm **In lại** (hoặc **Thử lại lỗi**).

## 3. In thử từng khung (ghi lại kết quả)

Trang **Máy in** → **In thử** → chọn khung, hoặc trang **Khung ảnh** → nút máy in trên từng thẻ khung đang bật (mặc định 2 Cut Ngà, 3 Cut Ngà, 4 Cut Đen, 6 Cut Ngà).

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

## 3b. Tự chỉnh nếu bản in chưa đẹp (trang Máy in, rồi In thử lại)

| Thấy gì | Chỉnh |
|---|---|
| Có viền trắng quanh ảnh | **Kiểu in: Tràn lề** (mặc định) |
| Bị cắt mất chữ hoặc QR ở mép | **Kiểu in: Có viền** |
| In ra bị phóng to, mất mép / bị xoay | **Máy in → Khi in → Khổ giấy** chọn đúng giấy đang lắp (SELPHY: Postcard; máy in ảnh: 2L hoặc L) |
| Màu in ra nhạt, thiếu đậm | thẻ **Màu tấm in** → **Độ đậm màu: Rất đậm** (mặc định là Đậm) |
| Màu quá gắt, da bị đỏ / cam | **Độ đậm màu: Vừa** |
| Ảnh in ra tối, màu vàng bị xỉn | **Độ sáng: +5%**, chưa đủ thì **+10%** |
| Ảnh nhạt, bị bạc / mờ như phủ sương | **Độ sáng: −5%** (và kiểm tra Độ đậm màu) |
| Tấm 4 Cut lộn đầu | bật **Xoay 4 Cut theo chiều ngược lại** |

Các tuỳ chọn này áp dụng cho mọi lần in sau, kể cả In lại. Ảnh gửi lên web không bị ảnh hưởng.

## 4. Thử hàng đợi và lỗi

- [ ] Bấm In thử 3 lần liên tiếp thật nhanh → máy in ra đủ 3 tấm lần lượt, không mất tấm nào
- [ ] Đo thời gian in một tấm (CP1500 khoảng 40–45 giây mỗi tấm postcard)
- [ ] **Tắt SELPHY** rồi bấm In thử → nhãn **Mất kết nối**, lệnh nằm chờ (trang **Lịch sử in**: Chờ máy in) → bật máy lại → tự in
- [ ] **Rút khay giấy** (giả hết giấy) rồi bấm In thử → ghi lại chuyện gì xảy ra:
  - báo Lỗi ngay, hay
  - đứng chờ (app tự bỏ qua sau tối đa **3 phút** rồi báo "Máy in không phản hồi sau 3 phút")
- [ ] Lắp lại giấy → **Lịch sử in** → **Thử lại lỗi**

## 5. Chạy thử một lượt thật

- [ ] Màn chờ → chọn khung → chụp → chọn ảnh → **In** → màn "Đang in!" hiện QR
- [ ] Máy in ra đúng tấm đó, QR trên giấy mở đúng trang ảnh và video
- [ ] Góc màn chờ hiện "máy in ok"

## 6. Gửi lại cho Claude

- Ảnh chụp các tấm in thử (thấy rõ mép, viền, màu, QR)
- Bảng ở mục 3 đã điền
- Ảnh chụp màn hình trang **Máy in** và **Lịch sử in** nếu có lỗi
- Thời gian in một tấm, và kết quả thử rút khay giấy

Nếu chỉnh ở mục 3b vẫn chưa ổn, Claude có thể chỉnh thêm:
- lề an toàn hoặc tỉ lệ tấm in nếu bị cắt mép hay có viền trắng
- chiều xoay của 4 Cut
- độ sáng và màu vàng nếu in ra tối
- thời gian chờ lỗi hoặc cách báo lỗi cho nhân viên

## Ghi chú kỹ thuật

- App gửi lệnh in qua `UIPrintInteractionController` tới máy in đã chọn (`UIPrinter(url:)`), loại ảnh `.photo`, khổ dọc,
  khổ giấy 283.5 × 419.5 pt (100×148 mm). App tự vẽ trang in (`PhotoPageRenderer`): "Tràn lề" phủ kín cả tờ giấy,
  "Có viền" nằm trọn trong vùng máy in in được. Lệnh in đi lần lượt từng cái: lệnh sau chỉ gửi khi lệnh trước đã báo xong
  hoặc đã quá 3 phút.
- File gửi máy in: `Booth/<ngày>/<giờ>/print.jpg` (4 Cut dùng `print_may_in.jpg`, đã xoay dọc). In thử nằm trong `Booth/in-thu/`.
- Code: `ios/Runner/AppDelegate.swift` (phần native), `lib/services/printer.dart` (hàng đợi in).
