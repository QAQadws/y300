# Sanitized mobile post fixtures

These synthetic forms reproduce the controls emitted by the supplied Yamibo Discuz 3.5 source in `E:/MyProjects/yamibo-bbs-dz35/upload/template/default/touch/forum/post.htm`, `post_editor_attribute.htm`, and `post_poll.htm`. The supplied `yamibo-bbs-template` does not override these post templates. No authenticated response, real credential or private post body is stored.

The ordinary form deliberately has no hidden fid, enctype, required classification marker or content maxlength, matching the template. The poll fixture uses a synthetic configured maximum of 32. Group labels and IDs are synthetic; repeated access value 20 demonstrates thresholds shared by multiple groups. An edit counterpart is constructed in adapter tests by changing action/identity/content and selected permissions.
