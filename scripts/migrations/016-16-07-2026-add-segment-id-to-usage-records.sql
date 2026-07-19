ALTER TABLE subscription.usage_records 
ADD COLUMN IF NOT EXISTS segment_id UUID;

COMMENT ON COLUMN subscription.usage_records.segment_id IS 'External Segment id. No physical FK.';
