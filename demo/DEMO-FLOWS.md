# WarpTalk — Kịch bản demo bảo vệ đồ án

5 flow chính. Mọi bước dưới đây đã được đối chiếu với route, controller và component
thật trong repo. Phần cuối có mục **"Những gì KHÔNG có"** — đọc trước khi lên sân khấu
để không hứa thừa.

**Soát ngày 2026-08-05, soát lại 2026-08-06** trên đúng bản **đang chạy production**
(`prod-20260806-livekit-reconnect-fix-v10`): backend `eb3177bf`, ai `f135e781`,
web `53cef00`, infra `6d1e10c` (migration 051).
Vòng 06-08 soát lại **Flow 2, Flow 3, bảng loại cuộc họp, panel Transcript, phòng chờ,
màn hình join và toàn bộ những gì 6 merge backend hôm nay chạm tới**. Flow 1, Flow 4,
Flow 5 giữ nguyên kết quả soát ngày 05-08 — cây web đang chạy **không đổi** so với hôm đó
(`53cef00` chỉ là merge của `development` sang `main`, nội dung y hệt), nên các bước
thuần frontend ở 3 flow đó chưa cần soát lại.

> ⚠️ **Cảnh báo về nhánh `development`.** Vài thứ đã merge vào `development` nhưng
> **chưa deploy**, đáng kể nhất là **WT-259 (language registry)**. Tài liệu này mô tả
> **cái đang chạy**, không phải cái đã có trong repo. Đừng demo theo code trên máy dev.

**Thứ tự khuyến nghị:** Flow 1 → Flow 3 → Flow 2 → Flow 4 → Flow 5.
Chuẩn bị giọng trước, để Flow 2 (họp) dùng voice clone làm cao trào, và Flow 4 có sẵn
dữ liệu thật từ cuộc họp vừa diễn ra.

---

## Flow 1 — Workspace: người, quyền, ngôn ngữ, chi phí

**Mục tiêu demo:** từ số 0 đến một workspace có người, có quyền, có thuật ngữ riêng,
có chính sách AI và có hạn mức tính bằng credit.

1. **Đăng ký / đăng nhập** — `/register` → mail verify → `/verify-email` → `/login`
   (có sẵn `/forgot-password` + `/reset-password` nếu hội đồng hỏi).
2. **Tạo workspace** — `/workspace/create`. Form chỉ có **Name** và **Logo URL** (tuỳ chọn) —
   không nhập slug, không chọn ngôn ngữ mặc định ở đây (ngôn ngữ mặc định nằm ở Settings).
   > ⚠️ **Tài khoản dùng email công cộng (gmail.com, outlook.com…) KHÔNG tạo được workspace.**
   > Trang chặn ngay với thông báo "Use a business email or join by invitation. Public email
   > domains cannot be system-verified for an Enterprise Workspace."
   > **Account demo tạo workspace bắt buộc phải là email doanh nghiệp** — kiểm tra trước,
   > vì đây là bước 2 của cả buổi. Người dùng email công cộng vẫn vào được workspace bằng
   > lời mời hoặc join request.
   > Ngoài ra còn một lỗi riêng cho tài khoản đã là *Internal* của một workspace khác.
3. **Giới thiệu điều hướng** — sidebar thật gồm:
   - **Home · Meetings · Transcripts · Voice Profiles**
     ("Meetings" có sẵn nút *Join by code* và *Create Meeting*; "Transcripts" trỏ tới `/[slug]/ai-summaries`)
   - **Members · Documents**, và nếu là Owner/Admin thêm **Invitations · Billing · Settings · Dashboard**
   - Nhóm **Platform** chỉ hiện với tài khoản system admin: Overview · Workspaces · Billing · Global Glossary

   > ⚠️ Các trang sau **không có trong sidebar**, phải mở bằng URL — hãy mở sẵn tab trước buổi bảo vệ:
   > `/[slug]/history` (có link từ trang *ended*),
   > `/[slug]/payment/plans`, `/terminology`, `/ai-chat`, `/[slug]/advanced`.
   > (`/[slug]/advanced` chỉ xuất hiện trong sidebar khi **đang ở trang settings và sidebar
   > đang thu gọn** — coi như phải mở bằng URL.)

4. **Mời thành viên** — `/[slug]/members` → Invite: email + role.
   Role chọn được là **Admin hoặc Member** — không mời thẳng ai làm Owner.
   API: `POST /api/v1/workspaces/{workspaceId}/invitations`.
5. **Quản lý lời mời** — `/[slug]/invitations` (chỉ Owner/Admin, và member kiểu *External*
   bị chặn hẳn — chỉ ra màn hình *Access Denied* nếu muốn khoe RBAC). Trang có **2 tab**:
   - **Invitations**: danh sách đã gửi + **Revoke**.
   - **Join requests**: người ngoài tự xin vào (`/workspace/join`) → Owner/Admin
     **Approve** (chọn cho vào dạng **Internal** hay **External**) hoặc **Reject**.

   Trang này **cũng có form mời riêng** (email + role), không nhất thiết phải quay lại Members.
   Mời xong nó hiện luôn một **link xem trước nội dung email** (`/dev/email/workspace-invite?…`) —
   tiện làm phương án dự phòng nếu mail thật không tới, nhưng đó là URL `/dev/`, cân nhắc có
   nên chiếu lên màn hình hay không.

   > ⚠️ **Không có nút Retry / resend lời mời trên giao diện.** Endpoint
   > `POST .../invitations/{invitationId}/retry-delivery` có ở backend nhưng frontend chưa gọi —
   > đừng hứa gửi lại được. Mời trượt thì Revoke rồi mời lại.

6. **Chấp nhận lời mời (máy 2)** — mở link mail → `/invitations/[token]` → Accept.
   > ⚠️ **Máy 1 phải F5 mới thấy member mới.** Luồng chấp nhận lời mời không phát sự kiện
   > realtime nào (khác với danh sách phòng ở Flow 2, cái đó có). Cứ refresh tự nhiên,
   > đừng đứng chờ.

7. **Quyền trên trang Members** — search, lọc theo pill **All / Owner / Admin / Member / Active**,
   **công tắc "được tạo meeting"** cho từng người
   (`PATCH .../members/{userId}` với `canCreateMeetings`), **remove member**, và
   **xuất danh sách ra Excel** (kèm cột Host Meetings Permission).
   Nhấn mạnh: **gate tạo meeting fail-closed** — tài khoản bị tắt công tắc này bấm
   Create Meeting sẽ bị **backend** chặn, không phải chỉ ẩn nút (WT-249).
   > ⚠️ **Đổi role member chưa có trên giao diện.** `PUT .../members/{userId}/role` và
   > `WorkspaceService.updateMemberRole` đều tồn tại nhưng **không component nào gọi**.
   > Nếu hội đồng hỏi thì trả lời đúng như vậy: backend đã có, UI chưa nối — đừng thao tác live.
   > **Transfer ownership thì ngược lại: đã có UI thật, chỉ là không nằm ở trang Members** — xem bước 12.
8. **Settings workspace** — `/[slug]/settings`. Nhiều hơn "chính sách thành viên":
   - Chung: default language, timezone, **max active rooms**, **artifact retention days**
   - Vận hành: enforce host approval default, **voice cloning enabled** (workspace tắt được
     voice clone toàn bộ), profanity filter
   - **Allowed target languages**
   - Cộng tác ngoài: verified domains, allow external collaboration,
     require verified domain for internal
   - **AI usage policy** (điểm ăn điểm về AI có kiểm soát): allow external LLM,
     **redact PII**, **DLP + keyword blacklist**, translation tone, và
     **kiểu kính ngữ tiếng Việt / keigo tiếng Nhật**
9. **Thuật ngữ riêng (Glossary)** — `/terminology`: tạo glossary (Name, Description,
   Source language, Target language) → thêm term (**Source term, Target term, Definition,
   Usage note**). Ngôn ngữ: en / vi / ja. Đây là input cho chất lượng dịch ở Flow 2.
10. **Documents** — `/[slug]/documents`: upload PDF/DOCX/XLSX/MD/ảnh, cờ **cho phép AI dùng**,
    quy trình duyệt (uploader/approver), access policy theo người, trích xuất text.
    Nói rõ: đây là **kho tri thức của workspace cho AI**, không phải biên bản họp
    (biên bản nằm ở artifact của cuộc họp — Flow 4).
11. **Gói dịch vụ & chi phí** — `/[slug]/payment/plans` chọn gói → `/[slug]/billing`.
    Mô hình **credit**, không phải "phút STT / ký tự TTS":
    Real-time Translation (STT) `cr/min` · AI Voice Synthesis (TTS) `cr/min` ·
    Custom Voice Cloning `cr/min` · AI Meeting Insights `cr/req` · AI Workspace Co-pilot Chat.
    Trang plans nhận cập nhật realtime qua SignalR khi thanh toán xong.
    Chốt ý: workspace không chỉ là nhóm người, mà là một đơn vị tính phí.
12. **Danger zone — chuyển quyền sở hữu & xoá workspace** — `/[slug]/advanced`
    (**không có trong sidebar**, mở bằng URL). Trang **chỉ Owner vào được**: Admin hay Member
    mở lên chỉ thấy màn hình *Access Denied* — thêm một chỗ khoe RBAC ngoài trang Invitations.
    - **Transfer Workspace Ownership**: chọn một thành viên trong dialog → xác nhận →
      người đó thành Owner, **người đang thao tác bị hạ xuống Admin và bị đá về `/workspace`**.
      API: `POST /api/v1/workspaces/{workspaceId}/members/transfer-ownership`.
    - **Delete Workspace**: phải **gõ đúng tên workspace** mới bấm xoá được.

    > ⚠️ Cả hai thao tác đều **không hoàn tác được** và làm mất luôn quyền của tài khoản đang demo.
    > Nếu muốn diễn live thì diễn trên **workspace rác**, đúng cái đã chuẩn bị cho Flow 5.
    > Trên workspace đang demo thì **chỉ mở trang cho hội đồng nhìn, đừng bấm**.

---

## Flow 3 — Giọng nói: giọng mặc định & voice profile

**Mục tiêu demo:** người dùng kiểm soát được giọng mình nghe và giọng mình cho phép nhân bản.

1. **Vào trang** — `/voice-profiles`.
2. **Giọng có sẵn** (khối "Giọng có sẵn" ở đầu trang): chọn ngôn ngữ → danh sách giọng
   từ thư viện nhà cung cấp → bấm một giọng để đặt làm **mặc định cho ngôn ngữ đó**.
   Vào phòng họp tự áp dụng, và chọn lại trong phòng thì lựa chọn trong phòng thắng.
   API: `PUT /api/v1/auth/voice-profiles/preferred-voice`.
   > ⚠️ Khối này chỉ có **Tiếng Việt và English**.
   > ⚠️ Catalog là cache lười — chưa có lần dịch nào cho ngôn ngữ đó thì danh sách **rỗng**
   > và trang sẽ ghi "Chưa có giọng nào cho ngôn ngữ này". **Phải warm trước khi demo.**
3. **Tạo voice profile** — *Create profile*: tên, ngôn ngữ (vi / en / ja), rồi
   **ghi âm trực tiếp trong trình duyệt hoặc upload file**. Có câu mẫu hiển thị sẵn để đọc.
   Trình duyệt **tự kiểm tra chất lượng mẫu** trước khi cho lưu: 5–120 giây, ≤ 20 MB,
   một người nói, phòng yên. Đây là chi tiết đáng chỉ ra — hệ thống không nhận mẫu rác.
   API: `POST /api/v1/auth/voice-profiles` (multipart).
4. **Danh sách profile** — mỗi hàng có badge trạng thái và nút **Delete**.
   Xoá để chứng minh người dùng kiểm soát được dữ liệu sinh trắc giọng nói của mình.
5. **Consent và nghe khác biệt giọng** → làm ở **Flow 2, trong phòng họp**.
   Công tắc đồng ý clone giọng là control **trong phòng**, không nằm ở trang này.

---

## Flow 2 — Cuộc họp thời gian thực

**Mục tiêu demo:** 2 người nói 2 ngôn ngữ khác nhau vẫn hiểu nhau, và nghe bằng giọng của nhau.

> ⚠️ **Cả Flow 2 đứng trên giả định LiveKit tải được audio trên production.**
> Bản `f135e781` (WT-269, sửa lỗi ingress dựng lại phòng LiveKit mỗi lần có track mới) mới
> deploy **hôm nay 2026-08-06** và **tại thời điểm soát tài liệu này, chưa ai xác nhận được
> một cuộc họp thật chạy trót lọt trên production.** Tài liệu không khẳng định là chạy được,
> cũng không khẳng định là hỏng.
> **Việc bắt buộc trước buổi bảo vệ: chạy thử 1 cuộc họp 2 máy end-to-end trên chính
> môi trường production sẽ dùng để demo.** Chạy được thì xoá cảnh báo này. Chưa chạy được
> thì **dùng video backup cho Flow 2** và nói thẳng là đang demo bản ghi.

1. **Tạo phòng** — nút **+** ở mục *Meetings* trên sidebar:
   - Tiêu đề, mô tả
   - **Loại cuộc họp** — đây là lựa chọn quan trọng nhất, vì backend cấu hình phòng từ nó:

     | Loại | Duyệt vào | Tắt mic khi vào | Tự ghi hình | Breakout | Số ghế |
     |---|---|---|---|---|---|
     | Event | – | – | – | ✓ | 100 |
     | Channel Meeting | – | – | – | ✓ | 50 |
     | Webinar | ✓ | ✓ | ✓ | – | 500 |
     | Company Meeting | – | ✓ | ✓ | ✓ | 500 |
     | Virtual Appointment | ✓ | – | – | – | 2 |
     | Live Event | ✓ | ✓ | ✓ | – | 1000 |

     Dialog hiện sẵn tóm tắt ("Duyệt trước khi vào / Vào là tắt mic / Tự ghi hình / Tối đa N người").

     > ⚠️ **Trong 4 cột trên, chỉ "Duyệt vào", "Breakout" và "Số ghế" là có hiệu lực thật.**
     > Hai cột còn lại mới chỉ là **chữ trong dialog**:
     > - **"Tắt mic khi vào"**: `MeetingRoom.MuteOnEntry` mặc định `false` và **không được
     >   seed từ loại cuộc họp** lúc phòng được tạo. Client chỉ đọc `JoinMeetingResponse.muteOnEntry`,
     >   tức chỉ tắt mic khi **host tự bật công tắc "Mute on entry" trong phòng**.
     > - **"Tự ghi hình"**: `TranslationRoomSettings.AutoRecord` được lưu nhưng **không có
     >   chỗ nào đọc để bật egress**. Đường duy nhất khởi động LiveKit Egress là
     >   `MeetingRoomService.SetRecordingAsync`, gọi từ **nút Record của host**.
     >
     > Nếu hội đồng hỏi "vậy Webinar có tự ghi không?" thì trả lời đúng: **loại cuộc họp
     > khai báo ý định đó, hệ thống chưa thi hành — muốn có bản ghi thì host bấm nút.**
     > Đừng chọn Webinar rồi ngồi chờ file xuất hiện.
     >
     > Ngược lại, **"Số ghế" là thật**: join bị chặn bằng 409 khi đủ ghế (WT-262), và ghế
     > chỉ tính người **CONNECTED** (WT-280) — host luôn được miễn.
   - **Tập ngôn ngữ của phòng** (vi · en · ja · ko · fr · es) — phòng được định nghĩa bằng
     **tập ngôn ngữ sẽ được nói**, *không* phải "ngôn ngữ nguồn → danh sách ngôn ngữ đích".
     Mỗi người chọn ngôn ngữ nói/nghe của riêng mình lúc vào phòng.

     > ℹ️ **WT-259 (language registry) đã vào `development`: dialog tạo phòng và màn hình
     > join giờ đọc chung một danh sách** — `languagesInScope("meeting")` trong
     > `src/lib/languages.ts`, đúng 6 dòng vi-VN · en-US · ja-JP · ko-KR · fr-FR · es-ES.
     > Nghĩa là **tạo phòng bằng ko / fr / es không còn làm kẹt người vào nữa**: họ chọn
     > được đúng thứ tiếng đó ở màn hình join (xem bước 3 Flow 2).
     > Vẫn nên diễn cặp **vi ↔ en** cho chắc, nhưng đó là lựa chọn kịch bản chứ không còn
     > là giới hạn của sản phẩm — đừng nói với hội đồng là chỉ hỗ trợ 3 ngôn ngữ.
   - Date & Time, mời theo email.

   > ✅ **Công tắc "Daily" trong menu ⋯ giờ là công tắc thật (WT-327).** Chọn **Daily** sẽ
   > **mở modal chọn giờ**: giờ trong ngày, ngày kết thúc, và múi giờ (đọc từ trình duyệt —
   > máy demo ở `Asia/Ho_Chi_Minh`). Modal in sẵn số cuộc họp sắp tạo, ví dụ
   > *"Every day at 08:00 · 31 meetings · Aug 7 – Sep 6"*, **trước khi** bấm Create.
   >
   > Bấm **Create Room** xong, backend tạo **mỗi ngày một phòng thật** (`translation_rooms` thật,
   > mỗi phòng một Room Code, một transcript, một hoá đơn riêng — không phải một dòng "ảo").
   > Ban đầu chỉ tạo trước **14 ngày**; một worker chạy mỗi 15 phút đẩy chân trời đó tiến lên.
   > Trên **Meetings** và **DailyTimeline**, mỗi phòng như vậy có huy hiệu **Daily**.
   >
   > ⚠️ **Vẫn phải bấm Start bằng tay.** Phòng lặp lại **không** tự bật dịch — đó là giao kèo
   > WT-248, đừng hứa là tới giờ nó tự chạy.
   >
   > ⚠️ **Không chọn cùng lúc "Date & Time" và "Daily".** Server từ chối request mang cả hai;
   > chọn Daily thì pill Date & Time tự biến mất.

   Bấm **Create Room** xong dialog chuyển sang màn hình xác nhận: hiện **Room Code**, nút
   **copy link mời** (`/join?code=…` — đây là chỗ lấy mã cho máy 2), nút **Configure**
   (mở luôn màn hình kiểm tra thiết bị) và nút **Join**.

   > ⚠️ **Muốn demo phòng chờ thì phải chọn loại có duyệt**: Webinar / Virtual Appointment /
   > Live Event. Chọn Event hay Channel Meeting là mọi người vào thẳng, không có gì để Admit.
   > (Cờ *enforce host approval default* trong Settings được lưu, nhưng phòng lấy yêu cầu
   > duyệt từ **loại cuộc họp**.)

2. **Danh sách phòng cập nhật realtime** — máy 2 được mời thấy phòng xuất hiện mà không cần F5 (WT-187).
3. **Vào phòng qua màn hình kiểm tra thiết bị** — link mời dạng `/join?code=<mã phòng>`:
   chọn mic / camera / loa, **thanh đo mức mic**, preview hình, bật/tắt **noise suppression**
   và **background blur**, chọn "tôi nói tiếng…" / "tôi nghe tiếng…", và chọn
   **Voice + Text hay Text only** → Join.

   > ⚠️ **Không có ô nhập tên hiển thị.** Tên lấy thẳng từ tài khoản
   > (`fullName` → `email` → "Guest"). Muốn tên đẹp trên tile thì **sửa profile trước buổi demo**,
   > không sửa được ở màn hình này. (WT-281 hôm nay chỉ sửa **hàng participant trong DB** —
   > trước đây host bị lưu là chuỗi "Host" — chứ **không** đổi tên trên tile LiveKit. Tile vẫn
   > lấy đúng cái client gửi lên, nên việc sửa `fullName` trước buổi demo **vẫn cần**.)
   > ⚠️ **Có HAI màn hình kiểm tra thiết bị, và chúng không giống nhau.** Cái mô tả ở bước này
   > là `/join?code=…`. Còn nút **Configure** ở màn hình xác nhận sau khi tạo phòng (và nút Join
   > ở trang chi tiết phòng) mở một modal khác: modal đó lọc ngôn ngữ **theo tập ngôn ngữ của
   > phòng**, và **host không có dropdown ngôn ngữ nào cả** — chỉ một dòng chữ "bạn là host,
   > ngôn ngữ nguồn là X". Host vào bằng đường đó sẽ có **nói = nghe = ngôn ngữ đầu tiên của
   > phòng**, tức **nghe tiếng chưa dịch**, và phải đổi bằng **voice/language picker trong phòng**.
   > **Cho host vào bằng `/join?code=…` để chọn được "tôi nghe tiếng…" ngay từ đầu.**
   > ⚠️ **Noise suppression và background blur mặc định TẮT** — muốn khoe thì phải tự bật.
   > ℹ️ Hai dropdown ngôn ngữ ở đây **lấy từ registry chung** — `languagesInScope("meeting")`
   > trong `src/lib/languages.ts`, không còn là danh sách cứng riêng của trang join (WT-259).
   > Nhờ vậy màn hình này **có đủ English · Vietnamese · Japanese · Korean · French · Spanish**,
   > đúng bằng tập ngôn ngữ dùng để tạo phòng: phòng khai ko / fr / es
   > thì người vào **vẫn chọn được** mấy ngôn ngữ đó ở màn hình này.
   > ⚠️ Nhưng danh sách vẫn **không lọc theo tập ngôn ngữ của phòng** — nó luôn là cả 6, nên
   > vẫn chọn nhầm được một thứ tiếng mà phòng không khai. Đọc kỹ tập ngôn ngữ của phòng trước khi chọn.
   > ⚠️ Người **chưa thuộc workspace** mở link này sẽ bị đá sang `/workspace/join?code=…`
   > (luồng xin vào ở Flow 1 bước 5), không vào thẳng phòng được.
4. **Phòng chờ** — `/[slug]/rooms/[id]/waiting`: host thấy hàng chờ và bấm **Admit**.
   Owner/Admin của workspace cũng admit được, không chỉ host (WT-188).
   Lobby tự hỏi lại mỗi 3 giây; host bấm **Start meeting** là mọi người được đẩy vào phòng.
   > ⚠️ Ở đây **chỉ có Admit**. Nút **Reject** nằm trong panel *People* sau khi đã vào phòng.
   > ⚠️ **Người đang chờ KHÔNG chiếm ghế.** Ghế chỉ tính trạng thái **CONNECTED**
   > (`TranslationRoomParticipantStatuses.SeatHolding`, đếm thẳng dưới database từ WT-280);
   > người đã LEFT / KICKED / REJECTED hoặc còn ngồi ở phòng chờ đều không tính.
   > Đây là câu trả lời nếu hội đồng hỏi "Virtual Appointment 2 ghế thì hàng chờ có làm đầy phòng không?" —
   > không, và host thì luôn được miễn hạn mức.
   > ⚠️ "Start meeting" ở lobby và "Start Translation" trong phòng gọi **cùng một endpoint** —
   > nếu host mở phòng từ lobby thì dịch **đã chạy sẵn** khi bước vào.
5. **Trong phòng** — `/room/[id]`: tiles LiveKit + thanh điều khiển.
   (`/[slug]/rooms/[id]` là trang **chi tiết/chuẩn bị** phòng — ghi chú, người tham dự, lời mời,
   nút Join — không phải màn hình họp.)
6. **Bật dịch** — **Start Translation**. Hệ thống **không** tự start (WT-248).
   Bật xong side panel tự mở sang tab Transcript.
   > ⚠️ Chỉ **host thật của phòng** start được. Owner/Admin workspace được cấp giao diện
   > giống host (admit, lock, mute all, recording…) và **vẫn thấy nút Start Translation**,
   > nhưng backend trả 403 nếu người bấm không phải `room.hostId`. Bấm bằng đúng máy host.
7. **Nói thử** — A nói tiếng Việt, B nghe tiếng Anh. Trong panel Transcript mỗi bong bóng hiện
   **câu gốc + bản dịch + nhãn "Vietnamese → English"**, chạy realtime. Đổi chiều để đối chứng.

   > ⚠️ **Bong bóng KHÔNG hiển thị độ tin cậy / độ chính xác nào cả.** `transcript-panel.tsx`
   > chỉ render câu gốc, bản dịch và nhãn ngôn ngữ — không có %, không có thanh, không có badge.
   > Đây là **khoảng trống thật** so với yêu cầu của cô hướng dẫn ("cho người dùng thấy mức độ
   > chính xác"). **Biết trước để trả lời thẳng, đừng chỉ vào một con số nào đó trên màn hình.**
   >
   > Câu trả lời trung thực nếu bị hỏi: hôm nay (WT-277 / WT-278) nhóm vừa **dọn đúng chỗ này**.
   > Trước đó hệ thống có một trường tên `confidence` trên bản dịch, nhưng nó **không đo bản dịch**
   > — nó là `avg_logprob` của STT, tức "nghe rõ tới đâu"; và khi thiếu giá trị thì nó bị lưu
   > thành **1.0 (tối đa)**, biến "không biết" thành "chắc chắn tuyệt đối".
   > Nay: giá trị không xác định lưu **NULL**, và con số STT được đổi tên thành
   > `source_stt_confidence` (migration 051) để **không ai đọc nhầm nó là chất lượng dịch**.
   > Điểm dừng của nhóm ở đây là **quyết định có chủ đích**: thà không hiện gì còn hơn hiện một
   > con số bịa. Một chỉ số chất lượng dịch thật (back-translation / COMET) là hướng phát triển tiếp,
   > và **đây là câu trả lời cho phần "hướng phát triển"**, không phải một tính năng đã có.
8. **Cao trào — giọng của chính người nói:**
   - Mở **voice picker** trên thanh điều khiển, đổi giọng cho ngôn ngữ đang nghe (nghe khác biệt ngay).
   - Bật **Voice clone consent** ("cho phép clone giọng tôi") → A nói tiếng Việt,
     B nghe **tiếng Anh bằng giọng của A**.
   - Chỉ rõ đây là consent **của chính người nói, tự bật, tắt được bất cứ lúc nào** — điểm
     ăn điểm về đạo đức/pháp lý AI.
   API: `POST /api/v1/translation-rooms/{roomId}/audio-routes/voice-clone-consent`.
9. **Glossary có tác dụng** — nói một câu chứa term đã tạo ở Flow 1, chỉ ra bản dịch dùng
   đúng thuật ngữ công ty thay vì dịch máy chung chung.
10. **AI gợi ý ngay trong transcript** — dải gợi ý một dòng nổi lên phía trên bong bóng,
    phân loại **Unanswered / Term / Action / Check / Reference**, tự biến mất sau 60 giây,
    không lưu lại. Hệ thống tự nhận xét cuộc họp mà không ai phải hỏi.
11. **Chọn 2–3 tính năng phụ trợ, đừng demo hết:**
    - **Chat đa ngữ**: dịch từng tin tại chỗ, gửi file, và **@WarpBot** — mention trợ lý
      ngay trong chat phòng họp để nó trả lời dựa trên phòng / tài liệu / thành viên.
    - **People**: tắt tuyến audio của một người, **spotlight**, raise hand, **transfer host**,
      **kick** (có xác nhận), Reject người trong hàng chờ.
    - **Host controls**: Lock room, Mute on entry, Mute all.
    - **Recording** (LiveKit Egress) — **host bấm nút Record thì mới có bản ghi**, kể cả với
      Webinar / Company Meeting / Live Event (xem cảnh báo ở bước 1: cột "Tự ghi hình" chưa
      được thi hành). Bấm xong mọi người trong phòng thấy chỉ báo đang ghi ngay, qua broadcast
      `RecordingStateChanged`.
      > ⚠️ Nhưng **người vào phòng SAU khi đã bắt đầu ghi thì không thấy chỉ báo** cho tới lần
      > bật/tắt tiếp theo: frontend khởi tạo `isRecording = false` và chỉ nghe broadcast.
      > Backend hôm nay đã trả `Recording` trong `JoinMeetingResponse` (WT-283) nhưng
      > **web đang chạy chưa đọc trường đó** (`types/meeting.ts` chưa có nó). Muốn khoe chỉ báo
      > thì **bấm Record khi cả 2 máy đã ở trong phòng**, đừng bấm trước.
    - **Breakout rooms**: chia nhóm, đặt thời lượng, hết giờ tự gom về phòng chính.
    - Reactions, đổi layout.
      (**Transcript-only** không phải control trong phòng — nó là lựa chọn *Text only* ở màn hình
      kiểm tra thiết bị, bước 3. Muốn khoe thì để máy 2 vào phòng ở chế độ Text only.)
12. **Host rời phòng** — host tắt tab thì hệ thống **thả quyền host, phòng thành không có host**;
    **không** tự bầu ai lên thay (WT-234 cố ý bỏ auto-elect, để không ai bỗng dưng có quyền host).
    Muốn chuyển quyền thì host phải chủ động **Transfer host** trong panel People trước khi rời.
    Nếu muốn kể chuyện này thì kể đúng như vậy — đó là lựa chọn thiết kế, không phải thiếu sót.
13. **Kết thúc** — End meeting → `/[slug]/rooms/[id]/ended`: trạng thái sinh artifact tự
    làm mới mỗi 5 giây, kèm 3 nút **Open artifacts · Submit feedback · View history**.
    (Trang này **không** có tóm tắt nội dung — tóm tắt ở Flow 4.)

---

## Flow 4 — Sau cuộc họp: transcript, tóm tắt, hỏi đáp

**Mục tiêu demo:** cuộc họp không bay đi mất — tra lại được, tóm tắt được, hỏi đáp được.

> ⚠️ Artifact mặc định là **HOST_ONLY**. Demo phần này bằng **tài khoản host**, nếu không
> máy 2 sẽ không thấy file nào.

### 4A. Lịch sử cuộc họp — `/[slug]/history`

1. Bảng các phòng đã kết thúc: **Ended · Language route · Time · People · Outputs**.
2. Filter: **All / Completed / Cancelled / With outputs**. Search theo tiêu đề, mã phòng,
   host, ngôn ngữ. (Không có filter khoảng thời gian, không phân trang.)
3. Panel phải: thông tin cuộc họp + danh sách **retained outputs** (Transcript / AI summary /
   Recording) để tải, kèm hạn lưu trữ theo chính sách workspace.
4. Artifact nào hiện **"Consent required"** thì lần bấm tải đầu tiên chính là thao tác duyệt —
   nói trước để không khựng.

### 4B. Transcript & AI Summary — `/[slug]/ai-summaries`

Đây là mục **"Transcripts"** trên sidebar. `/[slug]/transcript` chỉ là alias trỏ vào đúng
trang này, nên không tách làm hai bước.

5. Hàng đợi cuộc họp bên trái: search theo tiêu đề / mã phòng / host, kèm 4 pill lọc
   **All meetings · Export ready · Processing · Needs attention**. Chi tiết bên phải với
   3 tab: **Transcript · Summary · Artifacts**.
6. **Tab Transcript** — từng câu có timestamp + người nói, gom theo **phiên dịch**
   ("Translation 1", "Translation 2"… nếu trong cuộc họp có start/stop nhiều lần).
   Host **sửa được từng câu** (correction) khi transcript chưa chốt, và có nút
   **Finalize transcript** để khoá lại. Có **Copy transcript** và **Download** (.txt).
   > Chỉ hiển thị **câu gốc**. Không có cột dịch song ngữ và không có ô tìm kiếm trong transcript.
7. **Tab Summary** — **Overview / Decisions / Action items** (kèm người phụ trách).
   Tự sinh sau khi họp, thường dưới 1 phút; có trạng thái *Generating…* và trạng thái
   "không đủ nội dung để tóm tắt". Copy hoặc tải file summary.
8. **Tab Artifacts** — toàn bộ file gắn với cuộc họp (bản ghi, transcript, summary).

### 4C. Hỏi đáp trên dữ liệu họp

9. **Trợ lý WarpBot nổi ở mọi trang** — đây là surface nên demo. Nó **biết trang đang mở**,
   có slash command `/summarize`, `/action-items`, `/room-info`, `/summarize-doc`,
   `/extract-terms`, `/recent-meetings`, `/search-docs`, và **hiện rõ nó đang làm gì**
   ("Reading the transcript…", "Searching knowledge base…", "Looking up meeting summary…").

   > ⚠️ **Slash command bị khoá theo trang, và trang Transcripts KHÔNG nằm trong danh sách.**
   > Chỉ 5 surface đăng ký page-context: `/[slug]/documents`, trang chi tiết tài liệu,
   > `/[slug]/history`, `/[slug]/rooms/[id]`, và trong phòng họp. Đứng ở
   > `/[slug]/ai-summaries` gõ `/action-items` sẽ **không có gợi ý nào hiện ra**.
   > Muốn diễn `/summarize` và `/action-items` thì đứng ở **`/[slug]/history`** hoặc
   > **`/[slug]/rooms/[id]`** — đừng diễn ngay trên trang Transcripts vừa mở ở 4B.
10. `/ai-chat` là trang hội thoại rời, đơn giản hơn — chỉ mở nếu muốn khoe lịch sử hội thoại.
11. **Chốt giá trị** — từ audio thô → transcript → summary → trả lời được câu hỏi tự nhiên.
    Đây là chuỗi giá trị đầy đủ, không chỉ là một công cụ dịch.

---

## Flow 5 — Admin Portal

**Mục tiêu demo:** hệ thống có tầng vận hành toàn cục, không chỉ là app cho một workspace.

1. **`/admin`** — metric toàn hệ thống.
2. **`/admin/workspaces`** — directory tất cả workspace, filter/search, trạng thái
   **Active / Suspended / Deleted**.
3. **`/admin/workspaces/[workspaceId]`** — master–detail: overview + tab audit.
4. **Suspend / Reactivate** — **bắt buộc nhập lý do**, và người thực hiện luôn lấy từ token,
   không nhận từ body. API: `POST /api/v1/admin/workspaces/{id}/suspend|reactivate`.
   Nói rõ ranh giới quyền: gate bằng **platform role `admin`** seed trong `init-db.sql`,
   hoàn toàn khác role `Admin` của workspace — Owner/Admin workspace không vào được bằng đường nào.
5. **Audit log append-only** — `workspace.workspace_admin_actions` (chỉ SELECT + INSERT),
   tạo bởi migration `20260803120000_add_workspace_admin_actions.sql` và
   `20260803160000_generalize_admin_audit_log.sql` → không sửa được dấu vết.
6. **`/admin/global-glossary`** — thuật ngữ dùng chung toàn hệ thống: publish / archive /
   bulk import / audit. Phân biệt rõ với glossary riêng của workspace ở Flow 1.
7. **`/admin/billing`** — console billing nội bộ: biểu đồ usage, feature breakdown,
   top workspaces, subscriptions, invoices, alerts, service rates và **điều chỉnh credit**.

> **Ranh giới trung thực khi bị hỏi:** admin portal không có plan / trial / region /
> revenue theo từng workspace, vì schema `workspace.workspaces` chỉ có `is_active` và
> `deleted_at`; dữ liệu đó nằm ở billing service. Đây là ranh giới kiến trúc có chủ đích.

---

## Checklist chuẩn bị trước buổi bảo vệ

| Việc | Lý do |
|---|---|
| Account tạo workspace phải là **email doanh nghiệp** | Gmail/Outlook bị chặn ngay ở `/workspace/create` |
| **Warm voice catalog** cho mọi ngôn ngữ sẽ demo (nhất là `vi`) — chạy 1 lần dịch thật | Cache rỗng → picker trống → tưởng lỗi |
| Tạo phòng demo bằng loại **Webinar / Virtual Appointment / Live Event** | Loại khác không có phòng chờ, mất hẳn bước Admit |
| Diễn cặp **vi ↔ en** ở tập ngôn ngữ của phòng | Không còn là giới hạn (WT-259: join đã đủ 6 ngôn ngữ) — chỉ vì đó là cặp đã warm voice catalog và cả nhóm tập nhiều nhất |
| **Cho cả host và khách vào bằng `/join?code=…`** | Modal Configure không cho host chọn ngôn ngữ nghe → host nghe tiếng chưa dịch |
| **Chạy thử 1 cuộc họp 2 máy trên chính production** trước buổi bảo vệ | WT-269 vừa deploy hôm nay, chưa ai xác nhận LiveKit tải được audio |
| Nếu muốn khoe Recording thì **bấm Record khi cả 2 máy đã vào phòng** | Loại cuộc họp không tự ghi; và người vào sau khi đã ghi thì không thấy chỉ báo |
| Nhớ **Start meeting ở lobby = Start Translation** | Bấm ở lobby xong lại đứng chờ "bật dịch" trong phòng là hớ |
| Bấm **Start Translation bằng đúng máy host của phòng** | Owner/Admin workspace thấy nút nhưng bị 403 |
| Kiểm tra account demo **có công tắc "được tạo meeting"** | Gate fail-closed chặn ngay tại chỗ |
| Demo Flow 4 bằng **tài khoản host** | Artifact mặc định HOST_ONLY |
| Tạo sẵn 1 voice profile + 1 giọng mặc định đã chọn | Ghi âm và chờ xử lý live rất tốn thời gian |
| Tạo sẵn 1 cuộc họp cũ đã có transcript + summary | Flow 4 có dữ liệu đẹp, không phụ thuộc Flow 2 chạy trót lọt |
| Tạo sẵn 1 workspace "rác" để suspend ở Flow 5 | Không suspend nhầm workspace đang demo (dùng luôn cho Danger zone ở Flow 1 bước 12) |
| Mở sẵn tab các trang không có trong sidebar | `/[slug]/history`, `/[slug]/payment/plans`, `/terminology`, `/ai-chat`, `/[slug]/advanced` |
| **Không bấm Transfer ownership / Delete trên workspace đang demo** | Không hoàn tác được, và mất luôn quyền Owner giữa buổi |
| **Sửa `fullName` của cả 2 tài khoản demo trước** | Màn hình join không cho nhập tên; tile sẽ hiện nguyên địa chỉ email |
| Diễn slash command của WarpBot ở **History** hoặc **trang chi tiết phòng** | Trang Transcripts không đăng ký page-context, gõ `/` không ra gì |
| 2 máy + 2 tai nghe (chống hú) | Demo song ngữ bắt buộc 2 client |
| Có video backup Flow 2 & 3 | Mạng hội trường luôn là rủi ro số 1 |

---

## Những gì KHÔNG có — đừng hứa trên sân khấu

- **Poll / Q&A / Notes trong phòng họp**: đã gỡ khỏi side panel, giờ chỉ còn
  **Transcript · Chat · People**. (Backend polls vẫn còn nhưng không có UI.)
- **Nghe thử giọng (audio preview)** ở trang Voice Profiles — muốn so sánh giọng thì so
  trực tiếp trong phòng họp.
- **Transcript song ngữ side-by-side** và **tìm kiếm bên trong transcript** sau cuộc họp
  (ô search ở trang Transcripts lọc *danh sách cuộc họp*, không nhảy tới câu).
- **Filter khoảng thời gian / phân trang** ở History.
- **Chọn ngôn ngữ hiển thị cho AI summary.**
- **Mời thẳng vào role Owner** — chỉ mời được Admin/Member.
- **Đổi role member** — endpoint `PUT .../members/{userId}/role` và service đều có, nhưng
  **không UI nào gọi**. (Khác với **transfer ownership** — cái đó *có* UI thật ở
  `/[slug]/advanced`, đừng nói là chưa có.)
- **Gửi lại (retry/resend) lời mời** — endpoint có, UI chưa nối.
- **Danh sách member tự cập nhật khi ai đó Accept lời mời** — phải F5.
- **Tự bầu host mới khi host rớt** — WT-234 đã bỏ; phòng thành không có host, phải Transfer host trước.
- **Tạo workspace bằng email công cộng** — bị chặn ở form.
- **Chỉ số độ chính xác của transcript / bản dịch** — panel Transcript không hiện %, thanh
  hay badge tin cậy nào. Trường `confidence` cũ trên bản dịch **không đo bản dịch** (nó là
  `avg_logprob` của STT) nên WT-278 đã đổi tên thành `source_stt_confidence` và WT-277 chuyển
  giá trị không xác định về NULL thay vì 1.0. **Không hiện gì là có chủ đích, không phải quên** —
  chỉ số chất lượng dịch thật là hướng phát triển tiếp.
- **Tự ghi hình theo loại cuộc họp** — `AutoRecord` được lưu nhưng **không có consumer**;
  LiveKit Egress chỉ khởi động qua `SetRecordingAsync`, tức **nút Record của host**.
- **Tự tắt mic khi vào theo loại cuộc họp** — `MeetingRoom.MuteOnEntry` không được seed từ
  loại cuộc họp, mặc định `false`; chỉ có công tắc **Mute on entry** host bật trong phòng.
- **Chỉ báo "đang ghi" cho người vào phòng muộn** — backend đã trả `Recording` trong
  `JoinMeetingResponse` (WT-283) nhưng web đang chạy chưa đọc.
- **Chọn ngôn ngữ nghe/nói cho host trong modal Configure** — modal đó chỉ báo ngôn ngữ nguồn,
  không có dropdown; host vào bằng đường đó sẽ nói = nghe = ngôn ngữ đầu tiên của phòng.
  Cho host vào bằng `/join?code=…`.
- Bật/tắt **Voice Clone hay Recording ngay lúc tạo phòng** — voice clone là công tắc
  trong phòng, còn recording **chỉ bấm tay trong phòng** (loại cuộc họp không quyết định).
- **Lặp lại theo tuần / theo tháng** — chỉ có **Daily**. Cột `recurrence_type` đã nhận
  `WEEKLY`/`MONTHLY` nên sau này thêm không cần migration nữa, nhưng hôm nay server **từ chối
  thẳng** hai giá trị đó ("not available yet") chứ không lưu im lặng.
- **Sửa một chuỗi lặp sau khi tạo** — không đổi được giờ, không có "this and following".
  Chỉ có: huỷ **cả chuỗi** (dừng mọi buổi trong tương lai) hoặc huỷ **một buổi** (chuỗi vẫn chạy).
- **Đổi tên hiển thị lúc vào phòng** — tên lấy từ tài khoản, không sửa được ở màn hình join.
- **Slash command của WarpBot trên trang Transcripts** — trang đó không đăng ký page-context.
