import 'package:flutter/services.dart';

/// ルーレットに載せられるニックネームの上限。
const maxNicknameCount = 500;

/// ニックネームマスタのアセットパス。1行1名のテキストファイル。
const nicknameMasterAsset = 'assets/nicknames.txt';

/// マスタのテキストをニックネーム一覧に変換する。
///
/// 前後の空白を除き、空行は読み飛ばす。0件または [maxNicknameCount] 件を
/// 超える場合は [FormatException] を投げる。
List<String> parseNicknames(String source) {
  final names = source
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (names.isEmpty) {
    throw const FormatException('ニックネームマスタが空です');
  }
  if (names.length > maxNicknameCount) {
    throw FormatException(
      'ニックネームは最大$maxNicknameCount件です（${names.length}件あります）',
    );
  }
  return names;
}

/// アセットからニックネームマスタを読み込む。
Future<List<String>> loadNicknames({AssetBundle? bundle}) async {
  final source = await (bundle ?? rootBundle).loadString(nicknameMasterAsset);
  return parseNicknames(source);
}
