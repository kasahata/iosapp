import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'globals.dart'; // loggerが定義されていると仮定します

class MeasurementData {
  //計測場所詳細,計測場所,コード名,ページURL（開発）,ページURL（本番）
  late String placeDetail, place, codeName, devURL, prodURL;

  MeasurementData(
      this.placeDetail, this.place, this.codeName, this.devURL, this.prodURL);
}

//CSVデータの読み込み
Future<Map<String, MeasurementData>> importCSV() async {
  const String importPath = 'datas/appEventList.csv';
  Map<String, MeasurementData> impotrMap = {};
  String csv = await rootBundle.loadString(importPath);

  int i = 0;
  for (String line in csv.split("\n")) {
    final lineSplit = line.split(',');
    if (lineSplit.length < 5) {
      continue;
    }
    // 1行目はヘッダーなのでスキップ
    if (i == 0) {
      i++;
      continue;
    }

    String url = debug ? lineSplit[3] : lineSplit[4]; // 開発用URLは通常 lineSplit[3] (devURL) です。lineSplit[4] (prodURL) は本番用でしょう。
                                                    // ご自身のCSVの構成に合わせて適宜変更してください。

    impotrMap[url] = MeasurementData(
        lineSplit[0], lineSplit[1], lineSplit[2], lineSplit[3], lineSplit[4]);
  }
  return Future<Map<String, MeasurementData>>.value(impotrMap);
}

class AppsFlyerManager extends ChangeNotifier {
  late AppsflyerSdk _appsflyerSdk;
  Map<String, MeasurementData> _eventMap = {};

  // called by main.dart > initState()
  void afStart() async {
    logger.t('AppsFlyerManager()');

    _eventMap = await importCSV();

    // iOSかAndroidかで初期化処理を分ける
    if (Platform.isIOS) {
      // iOSの場合、ATTプロンプトを先に表示
      final TrackingAuthorizationStatus status =
          await AppTrackingTransparency.requestTrackingAuthorization();
      logger.i('ATT Status: $status'); // デバッグ用にステータスを出力

      final appsFlyerOptions = AppsFlyerOptions(
        afDevKey: "8dTkZaHxT87sFdF4HdaJUh",
        appId: "1280323739",
        showDebug: true,
        // ここを `true` に設定することで、ATTの同意が得られるまでAppsFlyer SDKの開始を待機させることができます。
        // `requestTrackingAuthorization()` を呼び出す前に設定する必要があります。
        waitForATTUserConsent: (status == TrackingAuthorizationStatus.authorized) ? false : true, // ユーザーが許可した場合は待機不要、それ以外は待機
        manualStart: true, // `initSdk` と `startSDK` を明示的に呼び出す
      );

      _appsflyerSdk = AppsflyerSdk(appsFlyerOptions);

      // ユーザーが同意した場合、または同意が得られなくてもSDKを初期化・開始するロジック
      // ATTのステータスに基づいてAppsFlyer SDKの開始を制御
      if (status == TrackingAuthorizationStatus.authorized) {
        await _appsflyerSdk.initSdk(
            registerConversionDataCallback: false,
            registerOnAppOpenAttributionCallback: false,
            registerOnDeepLinkingCallback: false);
        _appsflyerSdk.startSDK();
        logger.i('AppsFlyer SDK started with ATT authorized.');
      } else {
        // 同意が得られなかった場合でもAppsFlyer SDKを初期化・開始するかどうかは、
        // アプリケーションの要件とAppsFlyerのトラッキングポリシーによります。
        // IDFAが利用できないため、トラッキングの精度は落ちます。
        logger.w('User denied or restricted tracking. AppsFlyer SDK will start but with limited tracking capabilities.');
        await _appsflyerSdk.initSdk(
            registerConversionDataCallback: false,
            registerOnAppOpenAttributionCallback: false,
            registerOnDeepLinkingCallback: false);
        _appsflyerSdk.startSDK(); // 同意がなくてもSDKを開始
      }

    } else if (Platform.isAndroid) {
      final AppsFlyerOptions appsFlyerOptions = AppsFlyerOptions(
        afDevKey: "8dTkZaHxT87sFdF4HdaJUh",
        showDebug: true,
        manualStart: true,
      );

      _appsflyerSdk = AppsflyerSdk(appsFlyerOptions);

      // AndroidではATTは不要なので、すぐにSDKを初期化・開始
      await _appsflyerSdk.initSdk(
          registerConversionDataCallback: false,
          registerOnAppOpenAttributionCallback: false,
          registerOnDeepLinkingCallback: false);
      _appsflyerSdk.startSDK();
      logger.i('AppsFlyer SDK started on Android.');
    } else {
      // その他のプラットフォーム（Webなど）
      logger.w('Unsupported platform. AppsFlyer SDK will not initialize.');
      return; // サポートされていないプラットフォームの場合は処理を終了
    }

    // ここにあった共通のinitSdkとstartSDKの呼び出しは、
    // 各プラットフォームのif/elseブロック内に移動しました。
    // これにより、ATTの同意状況に応じてAppsFlyerの初期化を制御できます。
  }

  // urlに対応するイベントを送信
  bool logUrlEvent(String url) {
    if (_eventMap.containsKey(url)) {
      MeasurementData data = _eventMap[url]!;
      logEvent(data.codeName, {});
      return true;
    }

    return false;
  }

  // Send Custom Events
  logEvent(String eventName, Map eventValues) {
    _appsflyerSdk.logEvent(eventName, eventValues);
  }

  Widget buildMeasurementButtons() {
    return Column(
      children: _eventMap.values.map((data) {
        return TestMeasurementButton(
          place: data.codeName,
          onPressed: () => {logUrlEvent(data.devURL)},
        );
      }).toList(),
    );
  }
}

class TestMeasurementButton extends StatelessWidget {
  final String place;
  final Function onPressed;

  TestMeasurementButton({required this.place, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => onPressed(),
      child: Text(place),
    );
  }
}
