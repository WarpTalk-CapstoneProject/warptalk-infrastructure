# WarpTalk — Kịch bản demo bảo vệ (bản sân khấu)

Đây là bản để **diễn**: chỉ đường đi đúng, chỉ tính năng chạy được, mỗi flow kết bằng một
câu chốt giá trị. Không có bước nào cố tình cho hội đồng xem lỗi, màn hình *Access Denied*
hay tính năng còn thiếu.

Những ranh giới trung thực ("cái này chưa có", "cái kia mới là ý định") nằm ở
`DEMO-FLOWS.md` cùng thư mục — **đọc ở nhà, để trả lời khi bị hỏi**, không đọc trên sân khấu.

**Thứ tự:** Flow 1 → Flow 3 → Flow 2 → Flow 4 → Flow 5 (~30 phút).
Chuẩn bị giọng trước để Flow 2 dùng voice clone làm cao trào, và Flow 4 có dữ liệu thật
từ chính cuộc họp vừa diễn.

**Soát ngày 2026-08-13** trên cây `warptalk-web` nhánh `main` — **toàn bộ 5 flow**, gồm cả
trong phòng họp, Billing và Admin: điều hướng/sidebar, vị trí từng trang, dialog tạo phòng,
màn hình join, phòng chờ, thanh điều khiển và side panel trong phòng, trang kết thúc,
nơi transcript & summary sống, Member roles, Knowledge, đồng ý clone giọng, trang Billing,
trang Plans, và cả 5 trang admin.

> ⚠️ **Sản phẩm đã đổi so với kịch bản cũ — đừng diễn theo trí nhớ:**
> - **Không còn mục "Transcripts" trên sidebar.** Transcript, AI summary và file của một
>   cuộc họp nằm ngay trên trang cuộc họp đó: `/[slug]/rooms/[id]` → mục **Meeting record**.
> - **Không còn trang Invitations.** Lời mời và join request là các dòng trên **Members**.
> - Các trang đã có slug: `/[slug]/terminology`, `/[slug]/ai-chat`, `/[slug]/voice-profiles`.
> - Phòng họp live là `/[slug]/rooms/[id]/live` (link `/room/[id]` cũ tự chuyển hướng).
> - Có thêm **Knowledge** (`/[slug]/knowledge`) và **Member roles**
>   (`/[slug]/settings/member-roles`).
> - Lặp lại có **Daily / Weekly / Monthly**, và **Require approval** là công tắc riêng
>   trong menu ⋯ (không còn phụ thuộc loại cuộc họp).
> - **Bong bóng transcript giờ CÓ hiện % độ tin cậy** của bộ nhận dạng giọng nói (khi câu đó
>   đo được). Bản cũ ghi "không hiện gì" — đừng nói câu đó nữa, xem mục hỏi đáp cuối trang.
> - Gợi ý AI giờ là **badge trên bong bóng, bấm mới mở và không tự mất**, không còn là dải
>   một dòng tự biến mất sau 60 giây.

---

## Chuẩn bị — làm hết trước khi vào phòng bảo vệ

| Việc | Vì sao |
|---|---|
| Tài khoản tạo workspace là **email doanh nghiệp** | Gmail/Outlook bị chặn ngay ở `/workspace/create` |
| **Bật đồng ý clone giọng** cho cả 2 tài khoản tại `/[slug]/voice-profiles` | Không có bản ghi consent thì phòng họp **không clone**, cao trào Flow 2 mất |
| **Warm voice catalog** cho `vi` và `en` — chạy 1 lần dịch thật | Catalog là cache lười; rỗng thì voice picker không hiện |
| Sửa **fullName** của cả 2 tài khoản | Màn hình join không cho nhập tên; tile sẽ hiện nguyên email |
| Bật công tắc **"được tạo meeting"** cho tài khoản demo | Gate chặn ngay tại backend nếu tắt |
| **Cả host và khách vào bằng `/join?code=…`** | Đó là màn hình cho chọn "tôi nói / tôi nghe" ngay từ đầu |
| **Chạy thử 1 cuộc họp 2 máy trên chính production** | Đây là bước duy nhất phụ thuộc mạng và LiveKit |
| Tạo sẵn **1 voice profile** + chọn sẵn **1 giọng mặc định** | Ghi âm live tốn thời gian |
| Tạo sẵn **1 cuộc họp cũ đã có transcript + summary** | Flow 4 luôn có dữ liệu đẹp, không phụ thuộc Flow 2 |
| Nếu định khoe **đổi khuôn tóm tắt**: đổi thử trước trên cuộc họp cũ đó | Viết lại mất tới ~1 phút, đứng chờ trên sân khấu rất dài |
| Trong Settings, **để 1 ngôn ngữ ngoài danh sách được phép** (ví dụ bỏ Korean) | Flow 2 chỉ được vào chữ **Blocked** trong dialog tạo phòng — chính sách có hiệu lực thật, không phải chữ trang trí |
| Tạo sẵn **1 workspace "rác"** | Để Flow 5 suspend, không đụng workspace đang demo |
| Đăng nhập Flow 4 bằng **tài khoản host** | Artifact mặc định HOST_ONLY |
| Mở sẵn tab: `/[slug]/history`, `/[slug]/payment/plans`, `/[slug]/terminology`, `/[slug]/ai-chat` | Mấy trang này không nằm trên sidebar |
| 2 máy + 2 tai nghe | Chống hú, và demo song ngữ bắt buộc 2 client |
| Video backup Flow 2 | Mạng hội trường là rủi ro số 1 |

---

## Flow 1 — Workspace: người, quyền, ngôn ngữ, chi phí (~7 phút)

**Câu mở:** "WarpTalk không phải một công cụ dịch lẻ. Đơn vị của nó là workspace — có người,
có quyền, có thuật ngữ riêng, có chính sách AI, và tính phí được."

1. **Đăng nhập** — `/login`. (Có `/register` → verify email, và `/forgot-password` nếu hội đồng hỏi.)
2. **Tạo workspace** — `/workspace/create`: Name + Logo. Vào thẳng workspace mới.
3. **Giới thiệu điều hướng** — sidebar thật:
   - **Home · Meetings · Voice Profiles** (Meetings có sẵn *Join by code* và *Create Meeting*)
   - **Members · Documents**, và Owner/Admin có thêm **Knowledge · Billing · Settings · Dashboard**
   - Tài khoản system admin có thêm nhóm **Platform** — để dành cho Flow 5.
4. **Mời thành viên** — `/[slug]/members` → **Invite**: email + role (Admin / Member).
   Mời xong hiện luôn **link mời** để copy.
   Chỉ ra: danh sách này là **một chỗ duy nhất cho cả người đã vào và người đang trên đường vào** —
   mỗi dòng có trạng thái **Requested / Invited / Joined**, kèm chấm hiện diện online.
5. **Duyệt người xin vào** — trên chính trang Members: dòng **Requested** có **Approve**
   (chọn cho vào dạng *Internal* hay *External*) và **Reject**.
6. **Quyền** — vẫn trên Members: search, lọc, **công tắc "được tạo meeting"** cho từng người,
   **xuất danh sách ra Excel**. Nói: gate này **fail-closed** — tắt công tắc thì backend chặn,
   không phải chỉ ẩn nút.
7. **Đổi vai trò có kiểm soát** — `/[slug]/settings/member-roles` (Owner). Chọn một thành viên →
   hệ thống **hiện trước hệ quả** của việc thăng/giáng → **gõ đúng email để xác nhận** →
   áp dụng, và trả về một **biên nhận có mã audit**. Đây là điểm ăn điểm về quản trị:
   đổi quyền là hành động có xem trước, có xác nhận, có dấu vết.
8. **Settings workspace** — `/[slug]/settings`: ngôn ngữ mặc định, timezone, số phòng hoạt động
   tối đa, **danh sách ngôn ngữ được phép**, cộng tác với người ngoài, và
   **chính sách dùng AI**: cho phép LLM ngoài, **che PII**, **DLP + từ khoá cấm**, tông dịch,
   **kính ngữ tiếng Việt / keigo tiếng Nhật**.
   > Mẹo nối flow: **danh sách ngôn ngữ được phép** ở đây chính là thứ lát nữa làm một ngôn ngữ
   > hiện chữ **Blocked** trong dialog tạo phòng ở Flow 2 — nói trước một câu để lát sau chỉ vào.
9. **Thuật ngữ riêng** — `/[slug]/terminology`: tạo glossary → thêm term (Source, Target,
   Definition, Usage note). Nói trước: "lát nữa trong cuộc họp, thuật ngữ này sẽ xuất hiện
   đúng trong bản dịch."
10. **Documents** — `/[slug]/documents`: upload PDF/DOCX/XLSX/MD/ảnh, cờ **cho phép AI dùng**,
    quy trình duyệt, access policy theo người.
11. **Knowledge** — `/[slug]/knowledge`: chính là **những gì hệ thống đã học được** từ tài liệu
    và cuộc họp của workspace, mỗi dòng là một mẩu tri thức đọc được bằng mắt. Nói: "Trợ lý AI
    của WarpTalk không trả lời bằng trí tưởng tượng — đây là kho nó đọc."
12. **Gói dịch vụ & chi phí** — `/[slug]/billing`, bắt đầu từ 2 thẻ trên cùng:
    **AI credits remaining** (đã dùng bao nhiêu / tổng bao nhiêu / ngày gia hạn) và
    **Current plan**. Ba tab:
    - **Overview & Usage** — biểu đồ tiêu thụ theo ngày, **phân rã theo tính năng**
      (dịch realtime, TTS, clone giọng, AI insights, trợ lý), và phần phân bổ credit.
    - **Transaction History** — từng giao dịch credit, lọc theo loại / khoảng ngày / khoảng số tiền.
    - **Billing History** — hoá đơn, mở ra xem chi tiết.

    Nút **Export usage** xuất Excel; nút **Manage Plan & Credits** sang
    `/[slug]/payment/plans`: chọn gói **theo tháng / theo năm**, và **nạp thêm credit theo bậc**
    (nạp càng nhiều đơn giá càng giảm — 10 / 15 / 20%). Thanh toán xong trang tự cập nhật
    qua realtime, không cần F5.

    **Câu đáng nói:** "Mỗi giây dịch, mỗi câu tổng hợp giọng đều có giá và đều nằm trong một
    dòng sổ. Workspace không chỉ là nhóm người — nó là một đơn vị tính phí."

**Câu chốt:** "Một workspace là một đơn vị vận hành có chính sách và có hoá đơn."

---

## Flow 3 — Giọng nói: giọng bạn nghe và giọng bạn cho mượn (~4 phút)

**Câu mở:** "Người dùng kiểm soát hai thứ: giọng mình *nghe*, và giọng mình *cho phép nhân bản*."

1. **`/[slug]/voice-profiles`**.
2. **Giọng có sẵn** — chọn ngôn ngữ → thư viện giọng của nhà cung cấp → bấm một giọng để đặt
   làm **mặc định cho ngôn ngữ đó**. Vào phòng họp tự áp dụng; chọn lại trong phòng thì lựa chọn
   trong phòng thắng.
3. **Tạo voice profile** — *Create profile*: tên, ngôn ngữ, rồi **ghi âm ngay trong trình duyệt
   hoặc upload file**, có câu mẫu hiển thị sẵn. Trình duyệt **tự chấm chất lượng mẫu** trước khi
   cho lưu (5–120 giây, ≤ 20 MB, một người nói, phòng yên) — nhấn mạnh: hệ thống không nhận mẫu rác.
4. **Đồng ý clone giọng** — thẻ **Voice cloning** ngay trên trang: một chỗ **duy nhất, tìm lại
   được**, ghi rõ thu gì, dùng làm gì, giữ bao lâu, rút lại lúc nào cũng được — và hệ thống
   **lưu lại đúng câu chữ đã hiển thị cùng thời điểm bấm**. Bật **Allowed**.
   Nói thẳng: "Giọng là dữ liệu sinh trắc. Đồng ý phải cho một lần, biết rõ, và rút lại được —
   không giấu trong thanh công cụ giữa cuộc họp."
5. **Danh sách profile** — mỗi hàng có trạng thái và nút **Delete**: người dùng xoá được dữ liệu
   giọng của chính mình.

**Câu chốt:** "Nhân bản giọng ở đây là một quyền được cấp, không phải một mặc định."

---

## Flow 2 — Cuộc họp thời gian thực (~10 phút, cao trào)

**Câu mở:** "Hai người nói hai thứ tiếng, vẫn hiểu nhau — và nghe bằng giọng của nhau."

1. **Tạo phòng** — nút **+** ở mục *Meetings*:
   - **Loại cuộc họp** ở đầu dialog: Event · Channel Meeting · Webinar · Company Meeting ·
     Virtual Appointment · Live Event. Loại quyết định cấu hình phòng ở server (số ghế,
     breakout…).
   - **Tập ngôn ngữ của phòng** — pill cờ: một phòng được định nghĩa bằng **tập ngôn ngữ sẽ được
     nói**, không phải "nguồn → đích". Mỗi người tự chọn ngôn ngữ nói/nghe của mình lúc vào.
     Ngôn ngữ nào bị chính sách workspace cấm thì hiện **Blocked** kèm lý do — nối thẳng về
     Settings đã xem ở Flow 1. Chọn **Tiếng Việt + English**.
   - **Menu ⋯** — mở ra và khoe 2 thứ:
     - **Repeat**: bật lên là hiện ngay giờ, chọn **daily / weekly / monthly**, weekly thì tick
       các thứ, monthly thì chọn ngày, cộng ô **Repeat until**. Pill *Daily 08:00* hiện ngay
       cạnh — trạng thái không bao giờ im lặng. Nói: mỗi buổi là **một phòng thật**, có mã phòng,
       transcript và hoá đơn riêng.
     - **Require approval**: bật → có phòng chờ. (Bật cái này cho buổi demo.)
   - **Mời theo email** ngay trong dialog.
   - **Create Room** → màn hình xác nhận có **Room Code**, nút **copy link mời**
     (`/join?code=…` — lấy mã cho máy 2), **Configure** và **Join**.
2. **Danh sách phòng cập nhật realtime** — máy 2 thấy phòng hiện ra mà không cần F5.
3. **Màn hình kiểm tra thiết bị** — cả 2 máy mở `/join?code=…`: chọn mic / camera / loa,
   **thanh đo mức mic**, preview hình, bật **noise suppression** và **background blur**,
   chọn **"tôi nói tiếng…" / "tôi nghe tiếng…"**, chọn **Voice + Text** hay **Text only** → Join.
   (Cho máy 2 vào bằng *Text only* nếu muốn khoe chế độ chỉ phụ đề.)
4. **Phòng chờ** — `/[slug]/rooms/[id]/waiting`. Host thấy khối **"Asking to join (N)"** và bấm
   **Admit** từng người; khối **"In the room"** liệt kê người đã vào **kèm tuyến ngôn ngữ của
   họ** (ví dụ *Tiếng Việt → English*) — chỉ vào đây một giây, nó nói hộ cả sản phẩm.
   Bấm **Start meeting** là mọi người được đẩy vào phòng.
   Nói: người đang chờ **không chiếm ghế** — ghế chỉ tính người đã kết nối.
5. **Trong phòng** — `/[slug]/rooms/[id]/live`: tile LiveKit + thanh điều khiển. Trên thanh này
   có sẵn mic/camera, **chia sẻ màn hình**, đổi **layout**, **bật/tắt phụ đề** nổi trên video,
   và các dropdown "tôi nói / tôi nghe".
6. **Bật dịch** — **Start Translation** (bấm bằng đúng máy host). Side panel tự mở tab Transcript.
   > Nếu đã bấm **Start meeting** ở phòng chờ thì dịch đã chạy sẵn — cùng một endpoint.
7. **Nói thử** — A nói tiếng Việt, B nghe tiếng Anh. Mỗi bong bóng hiện **câu gốc + bản dịch +
   nhãn "Vietnamese → English"**, kèm tên người nói và mốc thời gian trong cuộc họp, chạy
   realtime. Đổi chiều để đối chứng.
   - Câu nào hệ thống đo được thì bong bóng có thêm **badge %** — đó là **độ tin cậy của bộ
     nhận dạng giọng nói** (nghe rõ tới đâu). Nếu chỉ vào nó, hãy gọi đúng tên như vậy,
     đừng gọi là "độ chính xác bản dịch".
   - Nếu trong buổi có **Stop rồi Start dịch lại**, transcript tự chia thành **Translation 1,
     Translation 2…** kèm khung giờ. Ai vào muộn sẽ thấy dòng *"You joined after N lines"* —
     những câu nói trước đó vẫn nằm phía trên, không mất.
   - Bật **phụ đề** trên thanh điều khiển để câu dịch chạy thẳng dưới khung hình cho hội đồng
     nhìn từ xa.
8. **Cao trào — giọng của chính người nói:**
   - Mở **voice picker** trên thanh điều khiển, đổi giọng cho ngôn ngữ đang nghe (có ghi rõ
     giới tính từng giọng) — nghe khác biệt ngay.
   - Bật **"dùng giọng clone của tôi"** → A nói tiếng Việt, **B nghe tiếng Anh bằng giọng của A**.
   - Chỉ rõ: quyền đã cấp ở Flow 3, còn đây là công tắc **của chính người nói, trong chính
     cuộc họp, tắt được bất cứ lúc nào**.
9. **Glossary có tác dụng** — nói một câu chứa term đã tạo ở Flow 1, chỉ vào bản dịch: đúng thuật
   ngữ công ty, không phải dịch máy chung chung.
10. **AI tự gợi ý trong transcript** — câu nào được AI để ý thì trên đầu bong bóng có một
    **badge nhỏ**, phân loại **Unanswered / Term / Action / Check / Reference**. **Bấm vào badge**
    thì gợi ý mở ra ngay tại chỗ, và nó **ở lại** — cuộn ngược về cuối buổi vẫn còn.
    Nói: "Hệ thống nhận xét cuộc họp mà không ai phải hỏi nó, nhưng nó chờ được mời mới nói."
11. **Chọn 2–3 tính năng phụ trợ thôi, đừng demo hết:**
    - **Chat đa ngữ**: dịch từng tin tại chỗ, gửi file, và **@WarpBot** ngay trong chat phòng họp.
      (Tab Chat có badge đếm tin chưa đọc khi đang đứng ở tab khác.)
    - **People**: spotlight, raise hand, tắt tuyến audio một người, **transfer host**.
    - **Host controls**: Lock room, Mute on entry, Mute all.
    - **Chia sẻ màn hình** — rẻ và ăn hình, thường đáng demo hơn breakout.
    - **Recording**: bấm **Record** khi **cả 2 máy đã ở trong phòng** — mọi người thấy chỉ báo
      đang ghi ngay lập tức.
    - **Breakout rooms**: chia nhóm, đặt thời lượng, hết giờ tự gom về phòng chính.
    - Reactions, đổi layout.
    > Side panel chỉ có đúng 3 tab: **Transcript · Chat · People**. Đừng hứa Poll / Q&A / Notes.
12. **Kết thúc** — **End meeting** → `/[slug]/rooms/[id]/ended`: danh sách file đang sinh, mỗi
    dòng tự cập nhật trạng thái. File nào xong thì **bấm vào chính dòng đó là mở ra đọc được
    nội dung ngay trên trang** — transcript và bản tóm tắt không cần tải về mới biết bên trong
    có gì. Nói một câu bắc cầu: "Còn để tra lại một cuộc họp bất kỳ sau này thì…" → Flow 4.

**Câu chốt:** "Rào cản ngôn ngữ biến mất mà danh tính giọng nói vẫn còn."

---

## Flow 4 — Sau cuộc họp: transcript, tóm tắt, hỏi đáp (~5 phút)

**Câu mở:** "Cuộc họp không bay đi mất. Nó tra lại được, tóm tắt được, và hỏi đáp được."

1. **Mở lại chính cuộc họp vừa họp** — **Meetings** → bấm vào cuộc họp đã kết thúc
   (`/[slug]/rooms/[id]`). Cuộn xuống dưới phần mô tả là mục **Meeting record**, 3 tab:
   - **Transcript** — từng câu có timestamp + người nói, gom theo phiên dịch. Host **sửa được
     từng câu** khi chưa chốt, và **Finalize** để khoá. Có **Copy** và **Download** (.txt).
   - **Summary** — **Overview / Decisions / Action items** (kèm người phụ trách), tự sinh sau
     khi họp, thường dưới 1 phút. Hai thứ đáng chỉ vào:
     - **Trích dẫn bấm được**: một mục trong tóm tắt bấm vào là **nhảy đúng về câu đã nói ra nó**
       trong transcript. Đây là câu trả lời cho "làm sao tin được bản tóm tắt?" — nó dẫn nguồn.
     - **Đổi khuôn tóm tắt**: dropdown góc trên chọn **General meeting / Standup /
       Candidate interview / Product demo / Technical discussion** → hệ thống **viết lại**
       cùng một cuộc họp theo khuôn khác. Cùng dữ liệu, khác câu hỏi.
       > Viết lại mất tới ~1 phút. Muốn ăn chắc thì **đổi trước ở nhà cho một cuộc họp cũ**,
       > lên sân khấu chỉ mở dropdown ra nói, hoặc bấm rồi nói tiếp việc khác trong lúc chờ.
   - **Artifacts** — toàn bộ file gắn với cuộc họp: bản ghi, transcript, summary; tải về ngay đây.
2. **Hỏi đáp bằng WarpBot ngay tại trang này** — trợ lý nổi ở góc **biết nó đang đứng ở đâu**:
   gõ `/summarize`, `/action-items`, `/room-info` và nó hiện rõ đang làm gì
   ("Reading the transcript…", "Searching knowledge base…"). Hỏi thêm một câu tự nhiên bằng
   tiếng Việt về nội dung cuộc họp.
3. **Lịch sử toàn workspace** — `/[slug]/history`: bảng các phòng đã kết thúc
   (**Meeting · Ended · Language route · Time · People · Outputs**), search theo tiêu đề / mã
   phòng / host / ngôn ngữ, lọc **All / Completed / Cancelled / With outputs**. Chọn một dòng,
   panel bên phải hiện **Ended · Duration · Participants · Route** và danh sách **Retained
   outputs** — bấm là tải. File nào ghi **"Consent required"** thì lần bấm đầu tiên chính là
   thao tác duyệt, nói trước một câu để không khựng.
   Slash command của WarpBot cũng chạy ở trang này.
4. *(Tuỳ chọn)* `/[slug]/ai-chat` — trang hội thoại rời, có lịch sử.

**Câu chốt:** "Từ audio thô → transcript → tóm tắt → trả lời được câu hỏi. Đó là chuỗi giá trị
đầy đủ, không chỉ là một công cụ dịch."

---

## Flow 5 — Admin Portal (~3 phút)

**Câu mở:** "Trên tất cả các workspace còn một tầng vận hành."

1. **`/admin`** — 4 thẻ số toàn hệ thống: **Active workspaces · Credits consumed ·
   Platform balance · Audit activity**, biểu đồ tiêu thụ, khối **Live operations** (cảnh báo
   tiêu thụ credit bất thường), top workspaces và phân rã theo tính năng. Trang tự làm mới
   mỗi phút — chỉ vào chấm **Live data** ở góc.
2. **`/admin/workspaces`** — directory mọi workspace, filter/search, trạng thái
   **Active / Suspended / Deleted**. Mở một workspace ra.
3. **Trang chi tiết workspace** — mở đúng **3 tab này**: **Overview** (số liệu + thông tin),
   **Knowledge** (đúng bảng tri thức đã xem ở Flow 1, nhìn từ tầng nền tảng), **Audit**.
   > 3 tab còn lại (Members / Usage / Billing) là chỗ đã chừa sẵn cho API chưa làm và nói thẳng
   > như vậy trên màn hình — đừng bấm vào khi đang diễn. Số liệu billing của một workspace nằm
   > ở trang Billing của chính workspace đó (Flow 1).
4. **Suspend workspace "rác"** — **bắt buộc nhập lý do**, người thực hiện lấy từ token.
   Suspend xong, ngay trên đầu trang hiện dải **"Suspended <thời điểm> — <lý do>"**, và nút đổi
   thành **Reactivate**. Nói rõ ranh giới quyền: gate bằng **platform role**, hoàn toàn khác
   role Admin của workspace.
5. **Tab Audit — append-only** — bảng chỉ cho SELECT + INSERT: dấu vết quản trị không sửa được.
6. **`/admin/global-glossary`** — thuật ngữ dùng chung toàn hệ thống, phân biệt với glossary
   riêng của workspace ở Flow 1.
7. **`/admin/billing`** — console billing nội bộ: usage, feature breakdown, top workspaces,
   subscriptions, invoices, alerts, **service rates** (đơn giá từng dịch vụ AI) và
   **điều chỉnh credit** cho một workspace.

**Câu chốt:** "Đây là một nền tảng nhiều tổ chức, có vận hành và có kiểm toán — không phải một
ứng dụng đơn lẻ."

---

## Nếu hội đồng hỏi (trả lời ngắn, đừng mở thêm màn hình)

- **"Con số % trên mỗi câu là gì?"** → Là **độ tin cậy của bộ nhận dạng giọng nói** cho câu đó —
  máy nghe rõ tới đâu. Nó **không** phải điểm chất lượng bản dịch, và hệ thống chỉ hiện khi thật
  sự đo được: không đo được thì bỏ trống, chứ không in "0%" hay "100%". Một chỉ số chất lượng
  *dịch* thật (back-translation / COMET) là hướng phát triển tiếp — trả lời đúng như vậy là
  vừa đủ và không hớ.
- **"Lặp lại theo tuần/tháng có sửa được sau khi tạo không?"** → Sửa được cả chuỗi; còn huỷ thì
  có cả hai mức: huỷ một buổi hoặc huỷ cả chuỗi.
- **"Có tự ghi hình theo loại cuộc họp không?"** → Bản ghi bắt đầu khi host bấm **Record**.
- **"Ai mở được phòng?"** → Phòng có **Require approval** thì chỉ host admit và mở. Phòng
  **không** bật thì bất kỳ người được mời nào cũng mở được — cố ý như vậy, để một host bận
  không giữ cả cuộc họp làm con tin.
- **"Bản tóm tắt có bịa không?"** → Bấm vào một dòng trong tóm tắt là nó nhảy về đúng câu trong
  transcript đã sinh ra dòng đó. Kiểm chứng được ngay tại chỗ.
- **"Admin portal xem được doanh thu / gói của từng workspace không?"** → Không, và đó là ranh
  giới kiến trúc: dữ liệu đó thuộc billing service, không thuộc bảng workspace. Ba tab
  Members / Usage / Billing trong trang chi tiết workspace nói thẳng điều đó trên màn hình.
- Mọi câu khác về "cái này có chưa": mục **"Những gì KHÔNG có"** cuối `DEMO-FLOWS.md`.
