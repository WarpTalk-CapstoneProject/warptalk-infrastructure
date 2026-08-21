-- ====================================================================
-- WarpTalk capstone demo seed — PART 5/5: rooms, participants, artifacts
-- Target database: warptalk_translation_room
--
-- Two rooms, on purpose:
--   b1  ENDED     — the pre-baked meeting Flow 4 reads (transcript + summary)
--   b3  SCHEDULED — so the Meetings list is not empty on arrival
--
-- The SCHEDULED room is NOT decoration. The rooms list hides ENDED rooms
-- behind a filter by default, so a workspace whose only room has ended shows
-- an empty Meetings page — which reads as "nothing was ever built here".
--
-- LANGUAGE CODES HERE ARE BARE ('vi', 'en', 'ja'), matching what the live
-- rooms hold. auth.user_settings uses full locales. See PART 1 and PART 4.
--
-- Idempotent: safe to re-run.
-- ====================================================================

\set ON_ERROR_STOP on

\set workspace_id     '019f1a00-0de0-7000-9200-0000000000aa'
\set owner_id         '019f1a00-0de0-7000-9200-000000000001'
\set room_id          '019f1a00-0de0-7000-9200-0000000000b1'
\set session_id       '019f1a00-0de0-7000-9200-0000000000b2'
\set upcoming_room_id '019f1a00-0de0-7000-9200-0000000000b3'

BEGIN;

-- ── 1. The finished meeting ─────────────────────────────────────────
-- settings mirrors the shape the room service writes (snake_case keys here,
-- unlike the workspace settings JSON which is PascalCase — the two services
-- serialise differently; verified on prod 2026-08-19).
--
-- requires_approval = false so a re-run of this room does not drop joiners
-- into the waiting room. Note that rooms created through the API are
-- persisted with requires_approval = true regardless of the request, so a
-- LIVE room in Flow 2 will still need the host to admit people.
INSERT INTO translation_room.translation_rooms (
    id, workspace_id, host_id, active_host_id, title, description,
    translation_room_code, status, translation_room_type, max_participants,
    source_language, target_languages, settings,
    started_at, ended_at, duration_seconds,
    is_active, created_at, created_by, updated_at, updated_by
)
VALUES (
    :'room_id', :'workspace_id', :'owner_id', NULL,
    'Sprint Review — Chuẩn bị bảo vệ',
    'Rà soát độ trễ dịch, nhân bản giọng nói và dữ liệu chi phí trước buổi bảo vệ.',
    'wtk-demo-cap', 'ENDED', 'EVENT', 100,
    'vi', '["vi", "en", "ja"]'::jsonb,
    jsonb_build_object(
        'auto_record',                        false,
        'mute_on_entry',                      false,
        'artifact_access',                    'ALL_PARTICIPANTS',
        'breakouts_enabled',                  true,
        'requires_approval',                  false,
        'participants_can_start_translation', true
    ),
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '1 day' + INTERVAL '2 minutes',
    120,
    true,
    NOW() - INTERVAL '1 day', :'owner_id',
    NOW() - INTERVAL '1 day', :'owner_id'
)
ON CONFLICT (id) DO UPDATE SET
    title                 = EXCLUDED.title,
    description           = EXCLUDED.description,
    translation_room_code = EXCLUDED.translation_room_code,
    status                = 'ENDED',
    source_language       = EXCLUDED.source_language,
    target_languages      = EXCLUDED.target_languages,
    settings              = EXCLUDED.settings,
    started_at            = EXCLUDED.started_at,
    ended_at              = EXCLUDED.ended_at,
    duration_seconds      = EXCLUDED.duration_seconds,
    is_active             = true,
    deleted_at            = NULL,
    updated_at            = NOW();

-- ── 2. Upcoming meeting ─────────────────────────────────────────────
INSERT INTO translation_room.translation_rooms (
    id, workspace_id, host_id, title, description,
    translation_room_code, status, translation_room_type, max_participants,
    source_language, target_languages, settings, scheduled_at,
    is_active, created_at, created_by, updated_at, updated_by
)
VALUES (
    :'upcoming_room_id', :'workspace_id', :'owner_id',
    'Họp bảo vệ thử — Capstone SEP490',
    'Buổi chạy thử toàn bộ kịch bản demo trước hội đồng.',
    'wtk-demo-run', 'SCHEDULED', 'EVENT', 100,
    'vi', '["vi", "en"]'::jsonb,
    jsonb_build_object(
        'auto_record',                        false,
        'mute_on_entry',                      false,
        'artifact_access',                    'ALL_PARTICIPANTS',
        'breakouts_enabled',                  true,
        'requires_approval',                  false,
        'participants_can_start_translation', true
    ),
    date_trunc('hour', NOW()) + INTERVAL '1 day' + INTERVAL '9 hours',
    true,
    NOW(), :'owner_id', NOW(), :'owner_id'
)
ON CONFLICT (id) DO UPDATE SET
    title            = EXCLUDED.title,
    description      = EXCLUDED.description,
    status           = 'SCHEDULED',
    scheduled_at     = EXCLUDED.scheduled_at,
    target_languages = EXCLUDED.target_languages,
    settings         = EXCLUDED.settings,
    is_active        = true,
    deleted_at       = NULL,
    updated_at       = NOW();

-- Guard: room codes are what a joiner types on stage. A collision with an
-- existing room would send them into someone else's meeting.
DO $assert$
DECLARE
    v_dupes int;
BEGIN
    SELECT count(*) INTO v_dupes
    FROM translation_room.translation_rooms
    WHERE translation_room_code IN ('wtk-demo-cap', 'wtk-demo-run')
      AND id NOT IN ('019f1a00-0de0-7000-9200-0000000000b1',
                     '019f1a00-0de0-7000-9200-0000000000b3');

    IF v_dupes > 0 THEN
        RAISE EXCEPTION 'Room code wtk-demo-cap / wtk-demo-run already belongs to % other room(s). '
            'Pick different codes in this script.', v_dupes;
    END IF;
END $assert$;

-- ── 3. Session ──────────────────────────────────────────────────────
-- transcripts.translation_room_session_id in PART 4 points here.
INSERT INTO translation_room.translation_room_sessions (
    id, translation_room_id, main_language, status, started_at, ended_at, created_at, updated_at
)
VALUES (
    :'session_id', :'room_id', 'vi', 'ENDED',
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '1 day' + INTERVAL '2 minutes',
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '1 day' + INTERVAL '2 minutes'
)
ON CONFLICT (id) DO UPDATE SET
    status    = 'ENDED',
    ended_at  = EXCLUDED.ended_at,
    updated_at = NOW();

-- ── 4. Participants ─────────────────────────────────────────────────
-- These ids are the speaker_participant_id values PART 4 writes onto the
-- transcript segments. status LEFT / connection_type WEBRTC match what the
-- live rows hold after a meeting ends.
--
-- is_using_voice_clone is set on the two Vietnamese speakers so the Flow 4
-- panel shows the clone actually having been in play.
INSERT INTO translation_room.translation_room_participants (
    id, translation_room_id, user_id, display_name, role,
    listen_language, speak_language, status, connection_type,
    is_translation_audio_enabled, is_using_voice_clone, is_external,
    joined_at, left_at, created_at, updated_at
)
VALUES
    ('019f1a00-0de0-7000-9200-0000000000c1', :'room_id',
     '019f1a00-0de0-7000-9200-000000000001', 'Huỳnh Thái Tú',     'HOST',
     'en', 'vi', 'LEFT', 'WEBRTC', true, true, false,
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes',
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes'),
    ('019f1a00-0de0-7000-9200-0000000000c2', :'room_id',
     '019f1a00-0de0-7000-9200-000000000002', 'Thân Thị Ngọc Vân', 'PARTICIPANT',
     'en', 'vi', 'LEFT', 'WEBRTC', true, true, false,
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes',
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes'),
    ('019f1a00-0de0-7000-9200-0000000000c3', :'room_id',
     '019f1a00-0de0-7000-9200-000000000003', 'Trần Mạnh Tuấn',    'PARTICIPANT',
     'vi', 'en', 'LEFT', 'WEBRTC', true, false, false,
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes',
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes'),
    ('019f1a00-0de0-7000-9200-0000000000c4', :'room_id',
     '019f1a00-0de0-7000-9200-000000000004', 'Ngô Xuân Hạnh Nhi', 'PARTICIPANT',
     'vi', 'en', 'LEFT', 'WEBRTC', true, false, false,
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes',
     NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day' + INTERVAL '2 minutes')
ON CONFLICT (id) DO UPDATE SET
    display_name    = EXCLUDED.display_name,
    role            = EXCLUDED.role,
    listen_language = EXCLUDED.listen_language,
    speak_language  = EXCLUDED.speak_language,
    status          = 'LEFT',
    left_at         = EXCLUDED.left_at,
    updated_at      = NOW();

-- ── 5. Artifacts ────────────────────────────────────────────────────
-- artifact_type values are the two the pipeline actually writes:
-- TRANSCRIPT_EXPORT (markdown) and SUMMARY_EXPORT (json). Status COMPLETED.
-- The body lives in `content`, not behind file_url — nothing is fetched from
-- object storage to render these, which is why they work with no MinIO object.

DELETE FROM translation_room.translation_room_artifacts
WHERE id IN ('019f1a00-0de0-7000-9200-0000000000f1',
             '019f1a00-0de0-7000-9200-0000000000f2');

INSERT INTO translation_room.translation_room_artifacts (
    id, translation_room_id, artifact_type, file_format, file_size_bytes,
    contains_raw_audio, contains_raw_video, consent_required,
    retention_until, status, content, created_at, created_by
)
VALUES (
    '019f1a00-0de0-7000-9200-0000000000f1', :'room_id',
    'TRANSCRIPT_EXPORT', 'markdown', NULL,
    false, false, false,
    NOW() + INTERVAL '30 days', 'COMPLETED',
$md$# Sprint Review — Chuẩn bị bảo vệ

**Ngày:** hôm qua · **Chủ toạ:** Huỳnh Thái Tú
**Ngôn ngữ gốc:** Tiếng Việt · **Bản dịch:** English, 日本語

---

**[00:01] Huỳnh Thái Tú (vi)**
Chào mọi người, hôm nay chúng ta rà soát lại tiến độ trước buổi bảo vệ.
> *EN:* Hi everyone. Today we're reviewing our progress before the defense.

**[00:06] Trần Mạnh Tuấn (en)**
Good morning. I'll start with the translation pipeline status.
> *VI:* Chào buổi sáng. Tôi sẽ bắt đầu với trạng thái của luồng dịch.

**[00:11] Trần Mạnh Tuấn (en)**
End-to-end latency at p50 is now two point six seconds across the three stages.
> *VI:* Độ trễ đầu-cuối ở p50 hiện là hai phẩy sáu giây qua ba giai đoạn.

**[00:19] Huỳnh Thái Tú (vi)**
Vậy phần lớn độ trễ còn lại nằm ở đâu?
> *EN:* So where does most of the remaining latency sit?

**[00:23] Trần Mạnh Tuấn (en)**
Most of it is the six second chunk window, not the models themselves.
> *VI:* Phần lớn nằm ở cửa sổ gom sáu giây, không phải ở bản thân các mô hình.

**[00:29] Thân Thị Ngọc Vân (vi)**
Cô đề nghị nhóm nêu rõ con số đó trong báo cáo, kèm theo cách đo.
> *EN:* I'd ask the team to state that number clearly in the report, along with the measurement method.

**[00:37] Huỳnh Thái Tú (vi)**
Em ghi nhận ạ. Nhi sẽ phụ trách phần biểu đồ đo độ trễ trong slide.
> *EN:* Noted. Nhi will take the latency chart in the slides.

**[00:44] Ngô Xuân Hạnh Nhi (en)**
I'll add the latency chart and the measurement method to slide twelve.
> *VI:* Em sẽ thêm biểu đồ độ trễ và cách đo vào slide mười hai.

**[00:50] Huỳnh Thái Tú (vi)**
Tiếp theo là nhân bản giọng nói. Trạng thái hiện tại thế nào?
> *EN:* Next is voice cloning. What's the current status?

**[00:56] Trần Mạnh Tuấn (en)**
Voice cloning runs inside the meeting now. The quality gate rejects clips under ten seconds.
> *VI:* Nhân bản giọng nói đã chạy ngay trong cuộc họp. Cổng chất lượng loại các đoạn dưới mười giây.

**[01:05] Thân Thị Ngọc Vân (vi)**
Nhóm cần chuẩn bị sẵn một hồ sơ giọng đã sẵn sàng trước khi lên bảo vệ.
> *EN:* The team should have a ready voice profile prepared before going up to defend.

**[01:13] Huỳnh Thái Tú (vi)**
Đồng ý ạ. Em sẽ chuẩn bị hồ sơ giọng cho cả bốn thành viên.
> *EN:* Agreed. I'll prepare voice profiles for all four members.

**[01:19] Ngô Xuân Hạnh Nhi (en)**
One more thing: the billing screen needs real usage data before the demo.
> *VI:* Còn một việc nữa: màn hình chi phí cần dữ liệu sử dụng thật trước buổi demo.

**[01:26] Huỳnh Thái Tú (vi)**
Được, em sẽ chuẩn bị dữ liệu sử dụng trước ngày bảo vệ.
> *EN:* Alright, I'll prepare the usage data before the defense day.

**[01:33] Thân Thị Ngọc Vân (vi)**
Vậy chốt lại ba việc: số đo độ trễ, hồ sơ giọng, và dữ liệu chi phí.
> *EN:* So three things are settled: the latency numbers, the voice profiles, and the billing data.

**[01:40] Huỳnh Thái Tú (vi)**
Rõ rồi ạ. Cảm ơn cô và cả nhóm.
> *EN:* Understood. Thank you, and thanks everyone.
$md$,
    NOW() - INTERVAL '1 day' + INTERVAL '3 minutes', :'owner_id'
);

-- The summary JSON. Shape is fixed by parseMeetingSummaryContent /
-- parseSummarySections in warptalk-web:
--   * any array key that is NOT summary/citations/templateKey/
--     insufficientData/translations renders as a section, titled from
--     SECTION_TITLES;
--   * an item is {text, atMs}, or {owner, task, atMs} for action items;
--   * an EMPTY section array is dropped rather than rendered as a heading over
--     nothing — which is why the real prod summaries look bare;
--   * atMs is what the "jump to this moment" control uses, so every value
--     below is a real segment start time from PART 4.
-- Built with jsonb_build_* rather than a literal so the Vietnamese text is not
-- hand-escaped.
INSERT INTO translation_room.translation_room_artifacts (
    id, translation_room_id, artifact_type, file_format, file_size_bytes,
    contains_raw_audio, contains_raw_video, consent_required,
    retention_until, status, content, created_at, created_by
)
SELECT
    '019f1a00-0de0-7000-9200-0000000000f2', :'room_id',
    'SUMMARY_EXPORT', 'json', NULL,
    false, false, false,
    NOW() + INTERVAL '30 days', 'COMPLETED',
    jsonb_build_object(
        'summary', 'Nhóm rà soát tiến độ trước buổi bảo vệ. Luồng dịch đã đạt độ trễ đầu-cuối 2,6 giây ở p50, phần lớn thời gian còn lại nằm ở cửa sổ gom sáu giây chứ không phải ở mô hình. Nhân bản giọng nói đã chạy được ngay trong cuộc họp, với cổng chất lượng loại bỏ các đoạn ghi âm dưới mười giây. Buổi họp kết thúc bằng ba đầu việc: bổ sung số đo độ trễ vào báo cáo, chuẩn bị hồ sơ giọng, và chuẩn bị dữ liệu chi phí cho màn hình billing.',
        'decisions', jsonb_build_array(
            jsonb_build_object('text', 'Nêu rõ con số độ trễ đầu-cuối kèm phương pháp đo trong báo cáo.', 'atMs', 29600),
            jsonb_build_object('text', 'Chuẩn bị sẵn hồ sơ giọng cho cả bốn thành viên trước buổi bảo vệ.', 'atMs', 65400),
            jsonb_build_object('text', 'Chốt ba hạng mục cần hoàn thành: số đo độ trễ, hồ sơ giọng, dữ liệu chi phí.', 'atMs', 93200)
        ),
        'actionItems', jsonb_build_array(
            jsonb_build_object('owner', 'Ngô Xuân Hạnh Nhi', 'task', 'Thêm biểu đồ độ trễ và phương pháp đo vào slide 12.', 'atMs', 44000),
            jsonb_build_object('owner', 'Huỳnh Thái Tú',     'task', 'Chuẩn bị hồ sơ giọng cho bốn thành viên.',           'atMs', 73100),
            jsonb_build_object('owner', 'Huỳnh Thái Tú',     'task', 'Chuẩn bị dữ liệu sử dụng cho màn hình chi phí trước ngày bảo vệ.', 'atMs', 86900)
        ),
        'openQuestions', jsonb_build_array(
            jsonb_build_object('text', 'Có nên giảm cửa sổ gom sáu giây để hạ độ trễ, và đánh đổi gì về độ chính xác?', 'atMs', 23300)
        ),
        'citations', jsonb_build_array(
            jsonb_build_object('key', 'summary', 'atMs', 11800),
            jsonb_build_object('key', 'summary', 'atMs', 56700),
            jsonb_build_object('key', 'summary', 'atMs', 93200)
        ),
        'translations', jsonb_build_object(
            'vi', jsonb_build_object(
                'summary', 'Nhóm rà soát tiến độ trước buổi bảo vệ. Luồng dịch đã đạt độ trễ đầu-cuối 2,6 giây ở p50. Nhân bản giọng nói đã chạy trong cuộc họp. Chốt ba đầu việc: số đo độ trễ, hồ sơ giọng, và dữ liệu chi phí.',
                'decisions', jsonb_build_array('Nêu rõ số đo độ trễ kèm cách đo trong báo cáo.', 'Chuẩn bị hồ sơ giọng trước buổi bảo vệ.'),
                'actionItems', jsonb_build_array(
                    jsonb_build_object('owner', 'Ngô Xuân Hạnh Nhi', 'task', 'Thêm biểu đồ độ trễ vào slide 12.'),
                    jsonb_build_object('owner', 'Huỳnh Thái Tú',     'task', 'Chuẩn bị hồ sơ giọng và dữ liệu chi phí.')
                )
            ),
            'en', jsonb_build_object(
                'summary', 'The team reviewed progress ahead of the capstone defense. The translation pipeline now reaches 2.6s end-to-end latency at p50, with most of the remaining time spent in the six-second chunk window rather than in the models. Voice cloning runs inside the meeting, and the quality gate rejects clips shorter than ten seconds. Three items were agreed: put the latency numbers in the report, prepare voice profiles, and prepare usage data for the billing screen.',
                'decisions', jsonb_build_array('State the end-to-end latency figure and its measurement method in the report.', 'Have voice profiles ready for all four members before the defense.'),
                'actionItems', jsonb_build_array(
                    jsonb_build_object('owner', 'Ngô Xuân Hạnh Nhi', 'task', 'Add the latency chart and measurement method to slide 12.'),
                    jsonb_build_object('owner', 'Huỳnh Thái Tú',     'task', 'Prepare voice profiles and the billing usage data.')
                )
            ),
            'ja', jsonb_build_object(
                'summary', 'チームは最終審査に向けて進捗を確認しました。翻訳パイプラインのエンドツーエンド遅延はp50で2.6秒に達し、残りの時間の大半はモデルではなく6秒のチャンク窓に起因します。音声クローンは会議中に動作し、品質ゲートが10秒未満の音声を拒否します。遅延の数値の報告書への記載、音声プロファイルの準備、課金画面用の利用データの準備の3点が決まりました。',
                'decisions', jsonb_build_array('報告書にエンドツーエンド遅延の数値と測定方法を明記する。', '審査前に4名分の音声プロファイルを用意する。'),
                'actionItems', jsonb_build_array(
                    jsonb_build_object('owner', 'Ngô Xuân Hạnh Nhi', 'task', 'スライド12に遅延グラフと測定方法を追加する。'),
                    jsonb_build_object('owner', 'Huỳnh Thái Tú',     'task', '音声プロファイルと課金用の利用データを準備する。')
                )
            )
        ),
        'templateKey', 'general',
        'insufficientData', false
    )::text,
    NOW() - INTERVAL '1 day' + INTERVAL '3 minutes', :'owner_id';

-- Fill in the byte sizes rather than typing them, so an edit above cannot make
-- the reported size a lie.
UPDATE translation_room.translation_room_artifacts
SET file_size_bytes = octet_length(content)
WHERE id IN ('019f1a00-0de0-7000-9200-0000000000f1',
             '019f1a00-0de0-7000-9200-0000000000f2');

-- ── 6. Assertions ───────────────────────────────────────────────────
DO $assert$
DECLARE
    v_participants int;
    v_artifacts    int;
    v_summary      jsonb;
BEGIN
    SELECT count(*) INTO v_participants
    FROM translation_room.translation_room_participants
    WHERE translation_room_id = '019f1a00-0de0-7000-9200-0000000000b1';

    IF v_participants <> 4 THEN
        RAISE EXCEPTION 'Expected 4 participants on the demo room, found %', v_participants;
    END IF;

    SELECT count(*) INTO v_artifacts
    FROM translation_room.translation_room_artifacts
    WHERE translation_room_id = '019f1a00-0de0-7000-9200-0000000000b1'
      AND status = 'COMPLETED'
      AND content IS NOT NULL
      AND artifact_type IN ('TRANSCRIPT_EXPORT', 'SUMMARY_EXPORT');

    IF v_artifacts <> 2 THEN
        RAISE EXCEPTION 'Expected both TRANSCRIPT_EXPORT and SUMMARY_EXPORT artifacts, found %', v_artifacts;
    END IF;

    -- The summary must parse as JSON and must not claim insufficient data,
    -- or the panel renders the "nothing to summarize" state on stage.
    SELECT content::jsonb INTO v_summary
    FROM translation_room.translation_room_artifacts
    WHERE id = '019f1a00-0de0-7000-9200-0000000000f2';

    IF (v_summary ->> 'insufficientData')::boolean IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'Summary artifact does not carry insufficientData = false';
    END IF;

    -- Every section must be non-empty: parseSummarySections drops empty ones,
    -- so an empty array here silently removes a heading from the demo.
    IF jsonb_array_length(v_summary -> 'decisions') = 0
       OR jsonb_array_length(v_summary -> 'actionItems') = 0
       OR jsonb_array_length(v_summary -> 'openQuestions') = 0 THEN
        RAISE EXCEPTION 'Summary has an empty section; it would not render at all';
    END IF;
END $assert$;

COMMIT;

\echo ''
\echo '--- Rooms (expect 1 ENDED with artifacts + 1 SCHEDULED) ---'
SELECT title, translation_room_code, status, source_language, target_languages, scheduled_at, ended_at
FROM translation_room.translation_rooms
WHERE workspace_id = :'workspace_id'
ORDER BY status;

\echo '--- Participants ---'
SELECT display_name, role, speak_language AS speak, listen_language AS listen, is_using_voice_clone, status
FROM translation_room.translation_room_participants
WHERE translation_room_id = :'room_id'
ORDER BY role DESC, display_name;

\echo '--- Artifacts ---'
SELECT artifact_type, file_format, status, file_size_bytes
FROM translation_room.translation_room_artifacts
WHERE translation_room_id = :'room_id'
ORDER BY artifact_type;
