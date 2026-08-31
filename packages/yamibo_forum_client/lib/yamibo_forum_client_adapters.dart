/// Experimental adapter, parser, mapper, and custom composition APIs.
///
/// These declarations are intended for composition roots and adapter tests.
/// They may change in a pre-1.0 minor release; application domain and
/// presentation code should import `yamibo_forum_client_contracts.dart`.
library;

export 'src/parsing/data_parse_exception.dart';
export 'src/adapters/thread_detail_api_mapper.dart';
export 'src/adapters/thread_detail_html_parser.dart';
export 'src/adapters/forum_client_adapter_factory.dart';
