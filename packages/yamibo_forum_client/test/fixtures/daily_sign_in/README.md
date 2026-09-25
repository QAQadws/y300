# Daily sign-in parser fixtures

- `unsigned.html` is a reduced reconstruction of the user-supplied unsigned mobile page. Its UID, day, token, and statistics are entirely synthetic; no original personal content or credential was copied.
- `signed.html` is inferred from the local `zqlj_sign` mobile template (`index.php` and `rili_1.php`), not captured from a live signed response.
- `login.html` and `error.html` are synthetic negative cases, not captured responses.

These fixtures prove only read-only page recognition. They do not establish how a live sign-in submission reports success or rejection.
