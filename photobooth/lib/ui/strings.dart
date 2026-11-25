import 'package:flutter/foundation.dart';

/// Guest-facing languages. The guest picks one on the start screen; it goes back to [vi]
/// after each guest. The admin screen stays Vietnamese.
enum Lang {
  vi('Tiếng Việt'),
  en('English'),
  ja('日本語');

  const Lang(this.name);
  final String name;
}

/// The language on screen now.
final lang = ValueNotifier<Lang>(Lang.vi);

/// The strings of [lang] (`T.now.start`, `T.now.pick(4)`…).
abstract final class T {
  static Strings get now => switch (lang.value) {
    Lang.vi => const _Vi(),
    Lang.en => const _En(),
    Lang.ja => const _Ja(),
  };
  static Strings of(Lang l) => switch (l) {
    Lang.vi => const _Vi(),
    Lang.en => const _En(),
    Lang.ja => const _Ja(),
  };
}

abstract class Strings {
  const Strings();

  // Start
  String get start;

  // Frame picker
  String get step1;
  String get chooseFrame;
  String get back;
  String get tapAFrame;
  String get startShooting;
  String frameHint(int photos, String shape);
  String get portrait;
  String get landscape;
  String get ivoryPaper;
  String get blackPaper;

  // Camera
  String get getReady;
  String get lookAtCamera;
  String get aboutToTake;
  String photos(int n);
  String get shot;
  String get seconds;

  // Photo picker
  String pickBest(int n);
  String get tapToPick;
  String secondsLeft(int s);
  String get filters;
  String get printPreview;
  String frameName(String label);
  String slotsInOrder(int n);
  String get retake;
  String get done;
  String doneMore(int n);
  String get processing;
  String get print;
  String get cannotProcess;

  // Thank you
  String get allDone;
  String get printing;
  String get scanToGet;
  String get openCamera;
  String get videosLater;
  String backIn(int s);

  /// On the print, under the date.
  String get printScanHint;

  /// Filter names by enum name (BoothFilter.name).
  Map<String, String> get filterNames;
}

class _Vi extends Strings {
  const _Vi();
  @override
  String get start => 'Chạm để bắt đầu';
  @override
  String get step1 => 'BƯỚC 1 / 3';
  @override
  String get chooseFrame => 'Chọn khung ảnh';
  @override
  String get back => 'Quay lại';
  @override
  String get tapAFrame => 'Chạm một khung';
  @override
  String get startShooting => 'Bắt đầu chụp';
  @override
  String frameHint(int photos, String shape) => '$photos ảnh · $shape';
  @override
  String get portrait => 'khổ dọc';
  @override
  String get landscape => 'khổ ngang';
  @override
  String get ivoryPaper => 'nền ngà';
  @override
  String get blackPaper => 'nền đen';
  @override
  String get getReady => 'Chuẩn bị nhé!';
  @override
  String get lookAtCamera => 'Nhìn vào camera';
  @override
  String get aboutToTake => 'Sắp chụp ';
  @override
  String photos(int n) => '$n tấm';
  @override
  String get shot => 'Tấm ';
  @override
  String get seconds => 'GIÂY';
  @override
  String pickBest(int n) => 'Chọn $n tấm đẹp nhất ';
  @override
  String get tapToPick => 'Chạm để chọn · chạm lại để bỏ';
  @override
  String secondsLeft(int s) => '$s giây';
  @override
  String get filters => 'BỘ LỌC';
  @override
  String get printPreview => 'XEM TRƯỚC TẤM IN';
  @override
  String frameName(String label) => 'Khung $label · ';
  @override
  String slotsInOrder(int n) => 'Ô 1 → $n theo thứ tự bạn chọn';
  @override
  String get retake => 'Chụp lại';
  @override
  String get done => 'Xong';
  @override
  String doneMore(int n) => 'Xong · còn $n';
  @override
  String get processing => 'Đang xử lý…';
  @override
  String get print => 'In';
  @override
  String get cannotProcess => 'Không xử lý được ảnh.\nBấm "Chụp lại" nhé!';
  @override
  String get allDone => 'Xong rồi!';
  @override
  String get printing => 'Đang in!';
  @override
  String get scanToGet => 'Quét mã để lấy ảnh & video';
  @override
  String get openCamera => 'Mở camera điện thoại và quét';
  @override
  String get videosLater => 'Ảnh có ngay, video Live lên sau 1–2 phút';
  @override
  String backIn(int s) => 'Tự về màn chờ sau $s giây';
  @override
  String get printScanHint => 'Quét mã để tải ảnh & video Live →';
  @override
  Map<String, String> get filterNames => const {
    'airy': 'Trong veo',
    'softMorning': 'Nắng sớm',
    'peachy': 'Hồng đào',
    'pinkDream': 'Hồng mơ',
    'sakuraPink': 'Hồng anh đào',
    'softGlow': 'Mờ mộng',
  };
}

class _En extends Strings {
  const _En();
  @override
  String get start => 'Tap to start';
  @override
  String get step1 => 'STEP 1 / 3';
  @override
  String get chooseFrame => 'Choose a frame';
  @override
  String get back => 'Back';
  @override
  String get tapAFrame => 'Tap a frame';
  @override
  String get startShooting => 'Start shooting';
  @override
  String frameHint(int photos, String shape) => '$photos photos · $shape';
  @override
  String get portrait => 'portrait';
  @override
  String get landscape => 'landscape';
  @override
  String get ivoryPaper => 'ivory';
  @override
  String get blackPaper => 'black';
  @override
  String get getReady => 'Get ready!';
  @override
  String get lookAtCamera => 'Look at the camera';
  @override
  String get aboutToTake => 'Taking ';
  @override
  String photos(int n) => '$n photos';
  @override
  String get shot => 'Photo ';
  @override
  String get seconds => 'SEC';
  @override
  String pickBest(int n) => 'Pick your best $n ';
  @override
  String get tapToPick => 'Tap to pick · tap again to remove';
  @override
  String secondsLeft(int s) => '$s s';
  @override
  String get filters => 'FILTERS';
  @override
  String get printPreview => 'PRINT PREVIEW';
  @override
  String frameName(String label) => '$label frame · ';
  @override
  String slotsInOrder(int n) => 'Slots 1 → $n in the order you tap';
  @override
  String get retake => 'Retake';
  @override
  String get done => 'Done';
  @override
  String doneMore(int n) => 'Done · $n more';
  @override
  String get processing => 'Processing…';
  @override
  String get print => 'Print';
  @override
  String get cannotProcess => 'Could not process the photos.\nPlease tap "Retake"!';
  @override
  String get allDone => 'All done!';
  @override
  String get printing => 'Printing!';
  @override
  String get scanToGet => 'Scan to get your photos & videos';
  @override
  String get openCamera => 'Open your phone camera and scan';
  @override
  String get videosLater => 'Photos now, Live videos in 1–2 minutes';
  @override
  String backIn(int s) => 'Back to start in $s s';
  @override
  String get printScanHint => 'Scan for your photos & Live videos →';
  @override
  Map<String, String> get filterNames => const {
    'airy': 'Crystal',
    'softMorning': 'Morning Sun',
    'peachy': 'Peach',
    'pinkDream': 'Pink Dream',
    'sakuraPink': 'Sakura',
    'softGlow': 'Soft Glow',
  };
}

class _Ja extends Strings {
  const _Ja();
  @override
  String get start => 'タップしてスタート';
  @override
  String get step1 => 'ステップ 1 / 3';
  @override
  String get chooseFrame => 'フレームを選ぶ';
  @override
  String get back => '戻る';
  @override
  String get tapAFrame => 'フレームをタップ';
  @override
  String get startShooting => '撮影スタート';
  @override
  String frameHint(int photos, String shape) => '$photos枚 · $shape';
  @override
  String get portrait => 'たて';
  @override
  String get landscape => 'よこ';
  @override
  String get ivoryPaper => 'アイボリー';
  @override
  String get blackPaper => 'ブラック';
  @override
  String get getReady => '準備はいい？';
  @override
  String get lookAtCamera => 'カメラを見てね';
  @override
  String get aboutToTake => '撮影 ';
  @override
  String photos(int n) => '$n枚';
  @override
  String get shot => '';
  @override
  String get seconds => '秒';
  @override
  String pickBest(int n) => 'ベスト$n枚を選んでね ';
  @override
  String get tapToPick => 'タップで選択 · もう一度タップで解除';
  @override
  String secondsLeft(int s) => '$s秒';
  @override
  String get filters => 'フィルター';
  @override
  String get printPreview => 'プリントのプレビュー';
  @override
  String frameName(String label) => '$label · ';
  @override
  String slotsInOrder(int n) => 'タップした順に 1 → $n';
  @override
  String get retake => '撮り直す';
  @override
  String get done => '完了';
  @override
  String doneMore(int n) => 'あと$n枚';
  @override
  String get processing => '処理中…';
  @override
  String get print => '印刷';
  @override
  String get cannotProcess => '写真を処理できませんでした。\n「撮り直す」を押してね！';
  @override
  String get allDone => '完成！';
  @override
  String get printing => '印刷中！';
  @override
  String get scanToGet => 'QRで写真と動画をゲット';
  @override
  String get openCamera => 'スマホのカメラで読み取ってね';
  @override
  String get videosLater => '写真はすぐ、Live動画は1〜2分後';
  @override
  String backIn(int s) => '$s秒後にスタート画面へ';
  @override
  String get printScanHint => 'QRで写真とLive動画をダウンロード →';
  @override
  Map<String, String> get filterNames => const {
    'airy': '透明感',
    'softMorning': '朝の光',
    'peachy': 'ピーチ',
    'pinkDream': 'ピンクドリーム',
    'sakuraPink': '桜',
    'softGlow': 'ソフトグロウ',
  };
}
