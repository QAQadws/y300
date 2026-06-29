// Phase 6: the thread post body model is now the shared canonical RichDocument
// (see reader_shared/domain/rich_text/document/rich_document.dart). These
// aliases keep the historical thread-specific names at every existing call
// site while the single model lives in reader_shared. No behavioural change:
// the canonical types are a field superset of the former thread model, and
// thread code dispatches on block subtype via `is` checks (no exhaustive
// switch), so promotion is transparent.
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

export 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';

typedef ThreadPostBodyBlock = RichBlock;
typedef ThreadPostBodyDocument = RichDocument;
typedef ThreadPostTextBlock = RichTextBlock;
typedef ThreadPostQuoteBlock = RichQuoteBlock;
typedef ThreadPostImageBlock = RichImageBlock;
typedef ThreadPostTextRun = RichRun;
typedef ThreadPostInlineImage = RichInlineImage;
