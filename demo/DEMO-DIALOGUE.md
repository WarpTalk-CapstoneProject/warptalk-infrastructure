# WarpTalk — Kịch bản thoại 3 ngôn ngữ (bản để học thuộc)

Cô dặn phải có kịch bản thoại. Đây là nó: **một phòng, ba ngôn ngữ cùng lúc**, mỗi người học
thuộc phần của mình.

`DEMO-SCRIPT.md` là kịch bản **sân khấu** — đi màn nào, bấm gì. File này là **lời nói**: đúng
những câu sẽ được thốt ra trong Flow 2, để bản dịch có cơ hội tốt nhất và để glossary hiện ra
là có ích thật.

---

## Ngành: hợp đồng gia công phần mềm B2B (QBR với khách Nhật)

**Không phải tôi chọn.** Nhóm đã chọn rồi — `glossary-en-vi.csv` và `glossary-vi-en.csv` trong
thư mục này đã có PO, SOW, SLA, MSA, UAT, công nợ, biên bản nghiệm thu, phụ lục hợp đồng, quyết
toán thuế. Đó là từ vựng hợp đồng / tài chính doanh nghiệp Việt Nam. Kịch bản chỉ đi theo.

Bối cảnh: **họp đánh giá kinh doanh hàng quý (QBR)** giữa một công ty gia công Việt Nam và một
khách hàng Nhật. Chọn QBR vì nó là lý do tự nhiên nhất để ba ngôn ngữ có mặt trong một phòng:
bên Việt nói tiếng Việt, bên Nhật nói tiếng Nhật, và tiếng Anh là ngôn ngữ hợp đồng — chính
xác tình huống mà một cuộc họp thật cần dịch.

**Vì sao ngành này là lựa chọn tốt để bảo vệ:** glossary của nhóm chứa **bẫy dịch sai có chủ
đích** — "công nợ" **không được** dịch là *public debt*, "ban giám đốc" **không được** dịch là
*board of directors*. Kịch bản dưới đây cố tình dùng đúng những từ đó. Nếu glossary làm việc,
hội đồng thấy nó bằng mắt; nếu không nạp glossary, câu dịch sẽ sai theo cách nhận ra được ngay.
Đó là bằng chứng, không phải lời quảng cáo.

---

## Phân vai

| Người | Ngôn ngữ nói | Vai |
|---|---|---|
| **Hạnh Nhi** | 🇻🇳 Tiếng Việt (`vi`) | Trưởng phòng dự án, bên gia công |
| **Ngọc Kỳ** | 🇯🇵 Tiếng Nhật (`ja`) | Đại diện khách hàng Nhật |
| **Mạnh Tuấn** | 🇬🇧 Tiếng Anh (`en`) | Kế toán / hợp đồng, ngôn ngữ trung gian |
| **Thái Tú** | (host) | Mở phòng, điều phối, không cần thoại dài |

Mỗi người **chỉ nói ngôn ngữ của mình** suốt cả cuộc. Đó là điểm của bài demo: không ai đổi
sang tiếng Anh để cho dễ.

---

## Chuẩn bị (làm trước, không làm trên sân khấu)

1. **Nạp glossary.** Workspace glossary → **Import** → `glossary-en-vi.csv` và
   `glossary-vi-en.csv`. Kiểm lại bằng cách tra "công nợ" trong danh sách — phải thấy
   *accounts receivable*.
2. **Kiểm phòng cho phép cả ba ngôn ngữ.** Workspace Settings → ngôn ngữ được phép phải có
   `vi`, `en`, `ja`. Nếu thiếu một cái, người đó không chọn được ngôn ngữ mình cần.
3. **Cả bốn tài khoản đang ở cùng một workspace.** Xem "Cảnh báo" cuối trang — đây là chỗ dễ
   làm hỏng buổi demo nhất.
4. Thu mẫu giọng trước cho ai sẽ trình diễn voice clone (theo `DEMO-SCRIPT.md`).

---

## Lời thoại

Đọc **chậm, hết câu, tách câu rõ**. Đừng nói chồng lời nhau — hai người nói cùng lúc là bài
kiểm tra khác, không phải bài này.

### Mở đầu — Tú (host)

> "Chúng ta bắt đầu buổi đánh giá quý ba. Mỗi người cứ nói ngôn ngữ của mình."

---

### 1. Nhi 🇻🇳 — mở phần Việt Nam

> "Chào anh Kỳ. Quý này chúng tôi đã hoàn thành ba mốc trong **phạm vi công việc**, và
> **biên bản nghiệm thu** của mốc thứ hai đã được hai bên ký."

> "Có một việc cần trao đổi: **công nợ** của quý hai vẫn chưa được thanh toán."

*(Đây là câu bẫy. "Công nợ" phải ra **accounts receivable** — nếu nó ra "public debt" thì
glossary chưa được nạp.)*

---

### 2. Kỳ 🇯🇵 — phía khách hàng trả lời

> 「ご報告ありがとうございます。第二マイルストーンの検収書は確認しました。」
>
> *(Cảm ơn báo cáo. Tôi đã xác nhận biên bản nghiệm thu của mốc thứ hai.)*

> 「支払いについては、社内の**取締役会**の承認待ちです。来週中に処理します。」
>
> *(Về thanh toán, đang chờ hội đồng quản trị trong nội bộ phê duyệt. Tuần sau sẽ xử lý.)*

---

### 3. Tuấn 🇬🇧 — kế toán / hợp đồng

> "Understood. On our side the invoice was issued with VAT, so we need the payment against
> the **milestone payment** schedule in the **master service agreement**, not against the
> **purchase order**."

> "One more item — the **change request** from last month expanded the **statement of work**.
> If we do not sign a **contract addendum**, this becomes **scope creep** and the **SLA** we
> committed to no longer covers it."

*(Ở đây có ba từ viết tắt liền nhau — MSA, PO, SLA. Đây là chỗ chứng minh glossary xử lý được
dạng nói tắt, không phải chỉ dạng đầy đủ.)*

---

### 4. Nhi 🇻🇳 — chốt lại và mở phần tiếp

> "Đúng vậy. Tôi sẽ gửi **phụ lục hợp đồng** trong hôm nay, và **người đại diện theo pháp
> luật** của chúng tôi sẽ ký."

> "Về nhân sự, **định biên nhân sự** cho quý bốn cần thêm hai người, hiện cả hai đang **thử
> việc**."

*(Bẫy thứ hai: "người đại diện theo pháp luật" phải ra đúng cụm **legal representative** —
glossary ghi rõ "bắt buộc dùng đúng cụm này trong mọi bản dịch".)*

---

### 5. Kỳ 🇯🇵 — kết

> 「承知しました。**UAT** の日程は来月の第二週でよろしいですか。」
>
> *(Đã hiểu. Lịch UAT tuần thứ hai tháng sau có được không?)*

> 「本番稼働は四半期末を目標にしたいと思います。」
>
> *(Chúng tôi muốn nhắm go-live vào cuối quý.)*

---

### 6. Tuấn 🇬🇧 — câu chốt cho AI summary

> "Agreed. To summarise: we sign the addendum today, payment clears next week, **user
> acceptance testing** starts in the second week of next month, and **go-live** is targeted
> for quarter end."

*(Câu này cố ý là một bản tóm tắt bằng lời. Sang Flow 4, khi AI summary hiện ra, hội đồng có
thể so bản máy tóm tắt với bản người vừa nói — và thấy nó không bịa.)*

---

## Chiều ngược lại — bắt buộc thử

Nhi đã yêu cầu: *"test ngược lại tiếng việt ch"*. Đừng chỉ trình diễn một chiều.

Sau đoạn 6, đổi ngôn ngữ **nghe** của Nhi sang tiếng Nhật rồi để Kỳ nói thêm một câu:

> 「では、来週の請求書を確認します。」
>
> *(Vậy tuần sau tôi sẽ kiểm tra hoá đơn.)*

Nhi phải **nghe được câu đó bằng tiếng Việt**. Đây là lượt kiểm chứng rằng ja → vi cũng chạy,
không chỉ vi → en.

---

## Cảnh báo — hai chỗ có thể làm hỏng buổi demo

### 1. Ba người ở ba workspace khác nhau (WT-468)

Màn pre-join đang lấy danh sách ngôn ngữ theo **workspace mà người vào đang chọn**, không phải
workspace sở hữu phòng. Nên nếu ba người ở ba workspace khác nhau, **mỗi người sẽ thấy một danh
sách ngôn ngữ khác nhau**, và người thiếu `ja` sẽ không chọn được tiếng Nhật.

Bản sửa đã có (backend + web đã merge) nhưng **chưa release lên production**. Cho tới lúc đó:
cho cả bốn tài khoản **cùng active một workspace**, và workspace đó phải cho phép đủ `vi`,
`en`, `ja`.

### 2. Glossary chưa có cặp tiếng Nhật

Hai file CSV hiện có là **en↔vi và vi↔en**. Không có cặp nào cho `ja`. Nên các câu tiếng Nhật
của Kỳ sẽ được dịch **không có glossary đỡ**.

Hai cách xử lý, chọn một trước khi bảo vệ:

- **Cách an toàn (khuyến nghị):** giữ lời thoại tiếng Nhật **tránh các từ bẫy**. Kịch bản trên
  đã làm vậy — câu của Kỳ dùng 検収書 (biên bản nghiệm thu) và 取締役会 (hội đồng quản trị) là
  những từ dịch máy xử lý được, còn "công nợ" và "người đại diện theo pháp luật" nằm ở lời
  của Nhi, nơi glossary có phủ.
- **Cách mạnh hơn:** tạo thêm một glossary `ja↔vi` với chừng 10 từ. Nhiều việc hơn, nhưng
  khi đó cả ba chiều đều có glossary và câu trả lời cho hội đồng gọn hơn.

Nếu hội đồng hỏi "tiếng Nhật có glossary không" — **trả lời thật**: chưa, và giải thích rằng
glossary là theo cặp ngôn ngữ nên thêm một cặp là thêm dữ liệu, không phải sửa code.

---

## Nếu hội đồng hỏi

**"Sao không để tất cả nói tiếng Anh cho nhanh?"**
Vì đó chính là chi phí mà sản phẩm này xoá. Một cuộc QBR thật giữa đội Việt Nam và khách Nhật
hiện phải có phiên dịch, hoặc phải hạ xuống mẫu số chung là tiếng Anh — và khi đó cả hai bên
đều nói thứ ngôn ngữ mình kém hơn, trong một cuộc họp bàn về tiền và hợp đồng.

**"Glossary có thật sự thay đổi kết quả không?"**
Có, và có thể kiểm ngay: "công nợ" không nạp glossary thì thành *public debt* — nghĩa hoàn toàn
khác, và là một câu nghe vẫn trôi chảy nên không ai phát hiện. Glossary của nhóm ghi thẳng
"tuyệt đối không dịch là public debt" trong phần ghi chú.

**"Vì sao chọn ngành này?"**
Vì đây là ngành mà dịch sai **tốn tiền**, không chỉ gây khó hiểu. "Ban giám đốc" dịch thành
*board of directors* là gán sai thẩm quyền phê duyệt cho một cơ quan khác.
