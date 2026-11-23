# lde-booth: máy chủ chia sẻ ảnh của photobooth LDE

Worker Cloudflare **riêng** cho app photobooth (`../photobooth`), không dùng chung code, bucket hay secret
với app Lensly đang chạy thật. Nó chạy ở `lenslycam.com/lde/*` nhờ một Workers route: route cụ thể hơn
custom domain `lenslycam.com` của Worker Lensly nên thắng, còn mọi đường dẫn khác vẫn về Lensly.
Các đoạn code dùng chung (style trang, ghép video trong trình duyệt) là **bản copy** từ
`Vintage-Came/server/share-worker`, không import.

| Đường dẫn | Việc |
|---|---|
| `PUT /lde/api/booth/<id>/<f>` | iPad gửi từng file (header `X-Booth-Key`): `print.jpg`, `layout.json`, `1..6.jpg`, `1..6.mp4` |
| `GET /lde/b/<id>` | Trang của khách: ảnh in, clip Live chạy trong từng ô, "Tải video ghép", tải từng ảnh / clip |
| `GET /lde/b/<id>/<f>` | Một file (`?dl=1` để tải về) |
| `GET /lde/b/<id>/status.json` | Số file đã lên (trang tự tải lại khi có file mới) |

File giữ 30 ngày (`BOOTH_TTL_DAYS`), cron dọn hằng ngày.

## Cài đặt (một lần, tài khoản Cloudflare jinwuk2021)

```sh
cd server
npm install
npx wrangler login                  # tài khoản có zone lenslycam.com
npx wrangler r2 bucket create lde-booth
npx wrangler r2 bucket lifecycle add lde-booth "Delete booth after 30 days" booth/ --expire-days 30
npx wrangler secret put BOOTH_KEY   # cùng giá trị BOOTH_KEY trong ../photobooth/booth_defines.json
npx wrangler deploy
```

Kiểm tra: `curl -I https://lenslycam.com/lde/b/abcdefghjkmn` trả 200 (trang "đang tải lên"), còn
`https://lenslycam.com/` vẫn là trang của Lensly.

## Test

```sh
npm test
```
