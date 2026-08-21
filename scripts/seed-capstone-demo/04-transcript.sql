-- ====================================================================
-- WarpTalk capstone demo seed — PART 4/5: transcript + glossary
-- Target database: warptalk_transcript
--
-- Two things live here:
--   A. Workspace glossaries (Flow 1, and the quality input for Flow 2)
--   B. A finished transcript for the pre-baked meeting (Flow 4)
--
-- Flow 4 exists so the transcript / AI-summary demo does not depend on the
-- live meeting in Flow 2 succeeding on stage.
--
-- LANGUAGE CODES HERE ARE BARE ('vi', 'en', 'ja') — that is what
-- transcripts.source_language, transcript_segments.original_language,
-- translation_contents.target_language and glossaries.* actually store on
-- prod. auth.user_settings uses full locales (vi-VN / en-US) instead. The two
-- conventions coexist; verified 2026-08-19. Do not unify them here.
--
-- The transcript text is AUTHORED demo content placed in the exact row shape
-- the real pipeline produces — it is not the output of an STT/MT run. It is
-- written to read like a real sprint review so it survives being projected.
--
-- Idempotent: safe to re-run.
-- ====================================================================

\set ON_ERROR_STOP on

\set workspace_id   '019f1a00-0de0-7000-9200-0000000000aa'
\set owner_id       '019f1a00-0de0-7000-9200-000000000001'
\set room_id        '019f1a00-0de0-7000-9200-0000000000b1'
\set session_id     '019f1a00-0de0-7000-9200-0000000000b2'
\set transcript_id  '019f1a00-0de0-7000-9200-0000000000d1'

BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- A. Glossaries
-- ════════════════════════════════════════════════════════════════════
-- term_count is a denormalised counter the service maintains itself; it is
-- recomputed from glossary_terms at the end of this script rather than typed
-- in, so a re-run cannot drift it.
INSERT INTO transcript.glossaries (
    id, workspace_id, name, description, source_language, target_language,
    term_count, is_active, created_at, created_by, updated_at, updated_by
)
VALUES
    ('019f1a00-0de0-7000-9200-0000000000e1', :'workspace_id',
     'WarpTalk — Kỹ thuật (VI→EN)',
     'Thuật ngữ kỹ thuật của sản phẩm WarpTalk, dùng để giữ nguyên cách dịch trong cuộc họp.',
     'vi', 'en', 0, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    ('019f1a00-0de0-7000-9200-0000000000e2', :'workspace_id',
     'WarpTalk — Product (EN→VI)',
     'Product and delivery vocabulary, kept consistent across English-speaking participants.',
     'en', 'vi', 0, true, NOW(), :'owner_id', NOW(), :'owner_id')
ON CONFLICT (id) DO UPDATE SET
    name            = EXCLUDED.name,
    description     = EXCLUDED.description,
    source_language = EXCLUDED.source_language,
    target_language = EXCLUDED.target_language,
    is_active       = true,
    deleted_at      = NULL,
    updated_at      = NOW();

DELETE FROM transcript.glossary_terms
WHERE glossary_id IN ('019f1a00-0de0-7000-9200-0000000000e1',
                      '019f1a00-0de0-7000-9200-0000000000e2');

INSERT INTO transcript.glossary_terms (
    id, glossary_id, source_term, target_term, definition, usage_note,
    domain, priority, is_active, created_at, created_by, updated_at, updated_by
)
VALUES
    -- VI → EN
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e1', 'nhân bản giọng nói', 'voice cloning',
     'Tạo một giọng tổng hợp mô phỏng giọng thật của người nói.',
     'Luôn dịch là "voice cloning", không dùng "voice copy".', 'ai', 9, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e1', 'độ trễ đầu-cuối', 'end-to-end latency',
     'Thời gian từ lúc người nói dứt câu đến lúc người nghe nghe được bản dịch.',
     'Giữ nguyên cụm "end-to-end", không rút gọn thành "latency".', 'engineering', 9, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e1', 'hồ sơ giọng', 'voice profile',
     'Bản ghi giọng đã được xử lý và lưu lại để tái sử dụng cho các cuộc họp sau.',
     'Không dịch thành "voice record".', 'product', 8, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e1', 'phòng chờ', 'waiting room',
     'Nơi người tham gia đứng chờ cho tới khi chủ toạ duyệt vào phòng.',
     'Thuật ngữ cố định trong giao diện.', 'product', 7, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e1', 'biên bản cuộc họp', 'meeting summary',
     'Bản tóm tắt do AI sinh ra sau khi cuộc họp kết thúc.',
     'Phân biệt với "transcript" là bản ghi lời nói đầy đủ.', 'product', 8, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e1', 'hạn mức', 'quota',
     'Giới hạn credit mà workspace được dùng trong một chu kỳ.',
     'Trong màn hình chi phí dịch là "quota", không phải "limit".', 'billing', 6, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    -- EN → VI
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e2', 'workspace', 'không gian làm việc',
     'Đơn vị tổ chức chứa thành viên, cuộc họp, tài liệu và hạn mức chi phí.',
     'Giữ nguyên "workspace" trong giao diện; chỉ dịch khi viết trong báo cáo.', 'product', 9, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e2', 'sprint review', 'họp rà soát cuối chu kỳ',
     'Buổi họp cuối mỗi chu kỳ phát triển để rà soát những gì đã hoàn thành.',
     'Không dịch thành "họp tổng kết".', 'process', 7, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e2', 'quality gate', 'cổng chất lượng',
     'Bước kiểm tra tự động từ chối dữ liệu đầu vào không đạt chuẩn.',
     'Dùng cho bước kiểm tra chất lượng đoạn ghi âm trước khi nhân bản giọng.', 'engineering', 8, true, NOW(), :'owner_id', NOW(), :'owner_id'),
    (gen_random_uuid(), '019f1a00-0de0-7000-9200-0000000000e2', 'credit', 'credit',
     'Đơn vị tính phí dùng chung cho STT, TTS, nhân bản giọng và các tính năng AI.',
     'Giữ nguyên, không dịch thành "điểm" hay "tín dụng".', 'billing', 9, true, NOW(), :'owner_id', NOW(), :'owner_id');

UPDATE transcript.glossaries AS g
SET term_count = sub.n, updated_at = NOW()
FROM (
    SELECT glossary_id, count(*) AS n
    FROM transcript.glossary_terms
    WHERE deleted_at IS NULL AND is_active
    GROUP BY glossary_id
) AS sub
WHERE g.id = sub.glossary_id
  AND g.id IN ('019f1a00-0de0-7000-9200-0000000000e1',
               '019f1a00-0de0-7000-9200-0000000000e2');

-- ════════════════════════════════════════════════════════════════════
-- B. Transcript for the pre-baked meeting
-- ════════════════════════════════════════════════════════════════════

-- Re-runnable: drop the child rows this script owns before rebuilding them.
-- Ordered children-first; there are no ON DELETE CASCADEs to rely on.
DELETE FROM transcript.segment_translation_links
WHERE segment_id::text LIKE '019f1a00-0de0-7000-9210-%';
DELETE FROM transcript.transcript_segments
WHERE transcript_id = '019f1a00-0de0-7000-9200-0000000000d1';
DELETE FROM transcript.translation_contents
WHERE id::text LIKE '019f1a00-0de0-7000-9220-%';

-- ── The conversation ────────────────────────────────────────────────
-- Two speakers on Vietnamese, two on English, so the translated column has
-- real work to do in both directions on screen.
--   speaker_participant_id values are the translation_room.* participant ids
--   PART 5 creates. Cross-service FKs do not exist, so the ordering between
--   PART 4 and PART 5 does not matter to the database — but it matters to the
--   UI, which joins them by id.
CREATE TEMP TABLE demo_script (
    seq          int  PRIMARY KEY,
    participant  uuid NOT NULL,
    speaker      text NOT NULL,
    lang         text NOT NULL,   -- bare code
    text         text NOT NULL,
    start_ms     int  NOT NULL,
    end_ms       int  NOT NULL,
    confidence   numeric NOT NULL,
    target_lang  text NOT NULL,   -- bare code
    translated   text NOT NULL,
    latency_ms   int  NOT NULL
) ON COMMIT DROP;

INSERT INTO demo_script VALUES
 (1,'019f1a00-0de0-7000-9200-0000000000c1','Huỳnh Thái Tú','vi',
  'Chào mọi người, hôm nay chúng ta rà soát lại tiến độ trước buổi bảo vệ.',
  1200,6400,0.96,'en',
  'Hi everyone. Today we''re reviewing our progress before the defense.',912),
 (2,'019f1a00-0de0-7000-9200-0000000000c3','Trần Mạnh Tuấn','en',
  'Good morning. I''ll start with the translation pipeline status.',
  6900,11300,0.97,'vi',
  'Chào buổi sáng. Tôi sẽ bắt đầu với trạng thái của luồng dịch.',845),
 (3,'019f1a00-0de0-7000-9200-0000000000c3','Trần Mạnh Tuấn','en',
  'End-to-end latency at p50 is now two point six seconds across the three stages.',
  11800,18600,0.95,'vi',
  'Độ trễ đầu-cuối ở p50 hiện là hai phẩy sáu giây qua ba giai đoạn.',1103),
 (4,'019f1a00-0de0-7000-9200-0000000000c1','Huỳnh Thái Tú','vi',
  'Vậy phần lớn độ trễ còn lại nằm ở đâu?',
  19100,22800,0.94,'en',
  'So where does most of the remaining latency sit?',764),
 (5,'019f1a00-0de0-7000-9200-0000000000c3','Trần Mạnh Tuấn','en',
  'Most of it is the six second chunk window, not the models themselves.',
  23300,29100,0.96,'vi',
  'Phần lớn nằm ở cửa sổ gom sáu giây, không phải ở bản thân các mô hình.',981),
 (6,'019f1a00-0de0-7000-9200-0000000000c2','Thân Thị Ngọc Vân','vi',
  'Cô đề nghị nhóm nêu rõ con số đó trong báo cáo, kèm theo cách đo.',
  29600,36700,0.95,'en',
  'I''d ask the team to state that number clearly in the report, along with the measurement method.',1247),
 (7,'019f1a00-0de0-7000-9200-0000000000c1','Huỳnh Thái Tú','vi',
  'Em ghi nhận ạ. Nhi sẽ phụ trách phần biểu đồ đo độ trễ trong slide.',
  37200,43500,0.96,'en',
  'Noted. Nhi will take the latency chart in the slides.',889),
 (8,'019f1a00-0de0-7000-9200-0000000000c4','Ngô Xuân Hạnh Nhi','en',
  'I''ll add the latency chart and the measurement method to slide twelve.',
  44000,50300,0.97,'vi',
  'Em sẽ thêm biểu đồ độ trễ và cách đo vào slide mười hai.',836),
 (9,'019f1a00-0de0-7000-9200-0000000000c1','Huỳnh Thái Tú','vi',
  'Tiếp theo là nhân bản giọng nói. Trạng thái hiện tại thế nào?',
  50800,56200,0.95,'en',
  'Next is voice cloning. What''s the current status?',798),
 (10,'019f1a00-0de0-7000-9200-0000000000c3','Trần Mạnh Tuấn','en',
  'Voice cloning runs inside the meeting now. The quality gate rejects clips under ten seconds.',
  56700,64900,0.94,'vi',
  'Nhân bản giọng nói đã chạy ngay trong cuộc họp. Cổng chất lượng loại các đoạn dưới mười giây.',1188),
 (11,'019f1a00-0de0-7000-9200-0000000000c2','Thân Thị Ngọc Vân','vi',
  'Nhóm cần chuẩn bị sẵn một hồ sơ giọng đã sẵn sàng trước khi lên bảo vệ.',
  65400,72600,0.96,'en',
  'The team should have a ready voice profile prepared before going up to defend.',1052),
 (12,'019f1a00-0de0-7000-9200-0000000000c1','Huỳnh Thái Tú','vi',
  'Đồng ý ạ. Em sẽ chuẩn bị hồ sơ giọng cho cả bốn thành viên.',
  73100,79200,0.97,'en',
  'Agreed. I''ll prepare voice profiles for all four members.',873),
 (13,'019f1a00-0de0-7000-9200-0000000000c4','Ngô Xuân Hạnh Nhi','en',
  'One more thing: the billing screen needs real usage data before the demo.',
  79700,86400,0.95,'vi',
  'Còn một việc nữa: màn hình chi phí cần dữ liệu sử dụng thật trước buổi demo.',1024),
 (14,'019f1a00-0de0-7000-9200-0000000000c1','Huỳnh Thái Tú','vi',
  'Được, em sẽ chuẩn bị dữ liệu sử dụng trước ngày bảo vệ.',
  86900,92700,0.96,'en',
  'Alright, I''ll prepare the usage data before the defense day.',806),
 (15,'019f1a00-0de0-7000-9200-0000000000c2','Thân Thị Ngọc Vân','vi',
  'Vậy chốt lại ba việc: số đo độ trễ, hồ sơ giọng, và dữ liệu chi phí.',
  93200,100400,0.96,'en',
  'So three things are settled: the latency numbers, the voice profiles, and the billing data.',1136),
 (16,'019f1a00-0de0-7000-9200-0000000000c1','Huỳnh Thái Tú','vi',
  'Rõ rồi ạ. Cảm ơn cô và cả nhóm.',
  100900,105300,0.97,'en',
  'Understood. Thank you, and thanks everyone.',742);

-- ── Transcript header ───────────────────────────────────────────────
-- status FINALIZED (the only non-RECORDING value in use on prod) and
-- is_current = true, which is what the room detail page filters on.
INSERT INTO transcript.transcripts (
    id, workspace_id, translation_room_id, translation_room_session_id, version, status,
    source_language, total_segments, total_duration_ms, last_sequence_order,
    is_active, is_current, timeline_anchor_at, finalized_at,
    created_at, created_by, updated_at, updated_by
)
SELECT
    :'transcript_id', :'workspace_id', :'room_id', :'session_id', 1, 'FINALIZED',
    'vi', (SELECT count(*) FROM demo_script), (SELECT max(end_ms) FROM demo_script),
    (SELECT max(seq) FROM demo_script),
    true, true,
    NOW() - INTERVAL '1 day',
    -- Finalisation lands after the last segment (105.3s) and after the room
    -- ends; PART 5 sets ended_at to anchor + 2 minutes.
    NOW() - INTERVAL '1 day' + INTERVAL '3 minutes',
    NOW() - INTERVAL '1 day', :'owner_id',
    NOW() - INTERVAL '1 day', :'owner_id'
ON CONFLICT (id) DO UPDATE SET
    status              = 'FINALIZED',
    source_language     = EXCLUDED.source_language,
    total_segments      = EXCLUDED.total_segments,
    total_duration_ms   = EXCLUDED.total_duration_ms,
    last_sequence_order = EXCLUDED.last_sequence_order,
    is_active           = true,
    is_current          = true,
    finalized_at        = EXCLUDED.finalized_at,
    deleted_at          = NULL,
    updated_at          = NOW();

-- ── Segments ────────────────────────────────────────────────────────
-- is_final = true throughout: these are settled segments, not the interim
-- partials the live pipeline also writes.
INSERT INTO transcript.transcript_segments (
    id, transcript_id, speaker_participant_id, speaker_name,
    original_text, original_language, start_time_ms, end_time_ms,
    confidence, sequence_order, is_corrected, is_final, created_at, updated_at
)
SELECT
    ('019f1a00-0de0-7000-9210-0000000000' || lpad(s.seq::text, 2, '0'))::uuid,
    :'transcript_id', s.participant, s.speaker,
    s.text, s.lang, s.start_ms, s.end_ms,
    s.confidence, s.seq, false, true,
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'
FROM demo_script AS s;

-- ── Translations ────────────────────────────────────────────────────
-- text_hash is the pipeline's dedup key over the source text; md5 matches the
-- 32-hex shape the live rows carry. translator_model 'gpt-4.1' is the model
-- the prod translation path actually reports.
INSERT INTO transcript.translation_contents (
    id, workspace_id, text_hash, target_language, translated_text,
    translator_model, confidence, source_stt_confidence, is_retranslated,
    latency_ms, status, created_at, updated_at
)
SELECT
    ('019f1a00-0de0-7000-9220-0000000000' || lpad(s.seq::text, 2, '0'))::uuid,
    :'workspace_id', md5(s.text), s.target_lang, s.translated,
    'gpt-4.1', 0.98, s.confidence, false,
    s.latency_ms, 'done',
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'
FROM demo_script AS s;

INSERT INTO transcript.segment_translation_links (
    segment_id, translation_content_id, target_language, is_current, delivered_at, created_at
)
SELECT
    ('019f1a00-0de0-7000-9210-0000000000' || lpad(s.seq::text, 2, '0'))::uuid,
    ('019f1a00-0de0-7000-9220-0000000000' || lpad(s.seq::text, 2, '0'))::uuid,
    s.target_lang, true,
    NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'
FROM demo_script AS s;

-- ── Assertions ──────────────────────────────────────────────────────
DO $assert$
DECLARE
    v_segments int;
    v_links    int;
    v_header   int;
    v_terms    int;
BEGIN
    SELECT count(*) INTO v_segments
    FROM transcript.transcript_segments
    WHERE transcript_id = '019f1a00-0de0-7000-9200-0000000000d1';

    SELECT count(*) INTO v_links
    FROM transcript.segment_translation_links AS l
    JOIN transcript.transcript_segments AS s ON s.id = l.segment_id
    WHERE s.transcript_id = '019f1a00-0de0-7000-9200-0000000000d1'
      AND l.is_current;

    -- Every segment must have exactly one current translation, or the
    -- transcript panel renders blank rows on one side.
    IF v_segments <> v_links THEN
        RAISE EXCEPTION 'Segment/translation mismatch: % segments but % current links',
            v_segments, v_links;
    END IF;

    SELECT total_segments INTO v_header
    FROM transcript.transcripts
    WHERE id = '019f1a00-0de0-7000-9200-0000000000d1';

    IF v_header <> v_segments THEN
        RAISE EXCEPTION 'transcripts.total_segments is % but % segment rows exist',
            v_header, v_segments;
    END IF;

    SELECT count(*) INTO v_terms
    FROM transcript.glossary_terms
    WHERE glossary_id IN ('019f1a00-0de0-7000-9200-0000000000e1',
                          '019f1a00-0de0-7000-9200-0000000000e2');

    IF v_terms <> 10 THEN
        RAISE EXCEPTION 'Expected 10 glossary terms, found %', v_terms;
    END IF;
END $assert$;

COMMIT;

\echo ''
\echo '--- Glossaries ---'
SELECT name, source_language, target_language, term_count
FROM transcript.glossaries WHERE workspace_id = :'workspace_id' ORDER BY name;

\echo '--- Transcript ---'
SELECT status, source_language, total_segments, total_duration_ms, is_current, finalized_at
FROM transcript.transcripts WHERE id = :'transcript_id';

\echo '--- First 4 segments with their translations ---'
SELECT s.sequence_order, s.speaker_name, s.original_language AS src,
       left(s.original_text, 44) AS original,
       t.target_language AS tgt, left(t.translated_text, 44) AS translated
FROM transcript.transcript_segments AS s
JOIN transcript.segment_translation_links AS l ON l.segment_id = s.id AND l.is_current
JOIN transcript.translation_contents AS t ON t.id = l.translation_content_id
WHERE s.transcript_id = :'transcript_id'
ORDER BY s.sequence_order
LIMIT 4;
