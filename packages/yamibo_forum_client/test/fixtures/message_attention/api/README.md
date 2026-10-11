# API message-attention fixture

`notice.json` is a synthetic, self-contained Discuz mobile API envelope. All
identities and text are fixture values; it contains no account credentials,
cookies, formhash, private-message body, or real forum response.

The public `Variables.notice` fields follow Discuz mobile API semantics:
`newpm` is a message-arrival bit mask, and notifications combine `newprompt`
with `newmypost`. The nonzero `newpush` demonstrates that this unrelated plugin
signal does not become a message hint. The viewed `space.uid` differs from the
verified viewer `member_uid` to guard against using a profile owner's identity.

Tests load the fixture with UTF-8 and use no App fixture or external Discuz
checkout. The parser receives decoded JSON maps, matching the existing network
representation; it does not decode JSON strings or inspect duplicate raw keys.
