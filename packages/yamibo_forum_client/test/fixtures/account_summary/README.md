# Desktop account summary fixture

`desktop.html` is a reduced, reconstructed and sanitized fixture based on the
desktop profile HTML supplied by the user and the local Discuz 3.5 templates
`home/space_profile_body.htm` and `home/space_userabout.htm`.

All account identifiers, names, avatar references and statistics are synthetic.
The fixture omits private profile fields, IP addresses, dates, session tokens,
cookies, scripts unrelated to viewer identity and any sign-in links. It keeps
the relevant desktop DOM structure, the distinct thread/reply links, and the
two identically named credit rows. Test mutations are synthetic, not captured
responses from a real account.
