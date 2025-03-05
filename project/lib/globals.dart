import 'package:logger/logger.dart';

/// ロガー
/// デバッグ用に一旦デフォルトロガーとしています。
/// 本番リリース時にはフィルタ設定を行ってください。
final logger = Logger();

/// デバッグフラグ
/// 現状、課金処理のpost先URLの切り替えに使用しています。
/// 本番リリース時にはフラグをfalseにしてください。
const debug = false;
