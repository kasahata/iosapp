import 'dart:async';
import 'dart:io';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'globals.dart';

class MeasurementData {
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

    String url = debug ? lineSplit[3] : lineSplit[4]; //開発用URL、本番では4

    impotrMap[url] = MeasurementData(
        lineSplit[0], lineSplit[1], lineSplit[2], lineSplit[3], lineSplit[4]);
  }
  return Future<Map<String, MeasurementData>>.value(impotrMap);
}

class AppsFlyerManager extends ChangeNotifier {
  late AppsflyerSdk _appsflyerSdk;
  Map<String, MeasurementData> _eventMap = {};
  bool _isSdkInitialized = false; // SDKが初期化済みかどうかを示すフラグを追加

  // SDKの初期化と開始を外部から呼び出すためのメソッド
  // main.dartからこのメソッドを呼び出すことで、ATTの承認後にSDKを初期化・開始できる
  Future<void> initializeAndStartAfSdk() async {
    if (_isSdkInitialized) {
      logger.t('AppsFlyer SDK already initialized.');
      return;
    }

    logger.t('AppsFlyerManager.initializeAndStartAfSdk()');

    _eventMap = await importCSV();

    // iOSかAndroidかで初期化処理を分ける
    if (Platform.isIOS) {
      final appsFlyerOptions = AppsFlyerOptions(
        afDevKey: "8dTkZaHxT87sFdF4HdaJUh",
        appId: "1280323739", // iOSの場合必須
        showDebug: true,
        // ここでは manualStart: true を設定しない
        // timeToWaitForATTUserAuthorization は `initSdk` の前に `waitForATTUserAuthorization` を明示的に呼ぶので不要
      );

      _appsflyerSdk = AppsflyerSdk(appsFlyerOptions);

      // ATTプロンプトの承認を待つ
      // この呼び出しは、`initSdk` の前に実行されるべき
      // `main.dart` で既に `AppTrackingTransparency.requestTrackingAuthorization()` を呼んでいるが、
      //念のためAppsFlyer SDK側でも承認を待つロジックを含めることで、より堅牢になる
      try {
        await _appsflyerSdk.waitForATTUserAuthorization(timeoutInterval: 60); // タイムアウトは適切に調整
        logger.t('AppsFlyer SDK: ATT user authorization granted or timed out.');
      } catch (e) {
        logger.e('Error waiting for ATT user authorization: $e');
      }

    } else if (Platform.isAndroid) {
      final AppsFlyerOptions appsFlyerOptions = AppsFlyerOptions(
        afDevKey: "8dTkZaHxT87sFdF4HdaJUh",
        showDebug: true,
        // ここでは manualStart: true を設定しない
      );
      _appsflyerSdk = AppsflyerSdk(appsFlyerOptions);
    }

    // SDKの初期化
    await _appsflyerSdk.initSdk(
        registerConversionDataCallback: false,
        registerOnAppOpenAttributionCallback: false,
        registerOnDeepLinkingCallback: false);

    // SDKの開始
    _appsflyerSdk.startSDK();
    _isSdkInitialized = true; // 初期化が完了したことをマーク
    logger.t('AppsFlyer SDK initialized and started successfully.');
  }

  // urlに対応するイベントを送信
  bool logUrlEvent(String url) {
    if (!_isSdkInitialized) {
      logger.w('AppsFlyer SDK is not initialized. Cannot log event: $url');
      return false;
    }

    if (_eventMap.containsKey(url)) {
      MeasurementData data = _eventMap[url]!;
      logEvent(data.codeName, {});
      return true;
    }

    return false;
  }

  // Send Custom Events
  logEvent(String eventName, Map eventValues) {
    if (!_isSdkInitialized) {
      logger.w('AppsFlyer SDK is not initialized. Cannot log event: $eventName');
      return;
    }
    _appsflyerSdk.logEvent(eventName, eventValues);
    logger.t('AppsFlyer event logged: $eventName with values: $eventValues');
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
