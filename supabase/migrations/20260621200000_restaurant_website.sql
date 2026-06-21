-- Session 2 refinement: store the restaurant's official website.
--
-- Place Details (New) returns websiteUri. Capturing it here gives Session 3's
-- menu fetch its best retrieval seed — the official site of the exact branch —
-- instead of a blind web search. Nullable: many small places have no website,
-- in which case Session 3 falls back to web search, then a photo upload.
alter table restaurants add column website text;
