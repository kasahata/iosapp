import 'dart:developer';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:project/measurements.dart';
import 'package:project/purchases.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:project/globals.dart';

// #docregion platform_imports
// Import for Android features.
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Import for iOS features.
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

Future<void> injectJavascript(WebViewController controller) async {
  logger.t('injectJavascript()');
  await controller.runJavaScript('''
    console.log('Inject Javascript');

    function SendId(id)
    {
      flutterChannel.postMessage(id);
    }

    const IosButtonNum = 6;
    for(var i = 0; i <= IosButtonNum;i++)
    {
      var num = ( '000' + i ).slice( -3 );
      const id = 'iOS.HorseCrystal.' + num;
      const button = document.getElementById(id);
      console.log('button id: ' + id + ', button: ' + button);
      if (button != null) {
        (function(btn) {
          btn.onclick = function() { SendId(btn.id); };
        })(button);
      }
    }

    const AndroidButtonNum = 6;
    for(var i = 1; i <= AndroidButtonNum; i++)
    {
      var num = ('000' + i).slice( -3 );
      const id = 'And.HorseCrystal.' + num;
      const button = document.getElementById(id);
      console.log('button id: ' + id + ', button: ' + button);
      if (button != null) {
        (function(btn) {
          btn.onclick = function() { SendId(btn.id); };
        })(button);
      }
    }
''');
}

void main() => runApp(
      const MaterialApp(
        home: MyApp(),
      ),
    );

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late final WebViewController _controller;
  late final Purchases _purchases = Purchases();
  late final AppsFlyerManager _appsFlyerManager = AppsFlyerManager();
  final _scaffoldKey = GlobalKey<ScaffoldMessengerState>();
  bool _isProcessing = false;

  // Appsflyer アプリ内イベントを送信する
  void sendAppFlyerEvent(String url) {
    bool logResult;
    try {
      logResult = _appsFlyerManager.logUrlEvent(url);
      if (logResult == true) {
        logger.t("Event logged successfully: $url");
      }
    } catch (e) {
      logger.t("Failed to log event: $e");
    }
  }

  // AppTrackingTransparencyの初期化とAppsFlyer SDKの開始を行う新しいメソッド
  Future<void> _initATTAndAppsFlyer() async {
    logger.t('_initATTAndAppsFlyer started.');

    // AppTrackingTransparencyの初期化（プロンプト表示と承認待機）
    // _initATT() メソッドは不要になり、ここに統合します
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      // プロンプトが初めて表示される場合
      // 少し待機することで、UIの準備が整い、プロンプトがスムーズに表示される可能性が高まります。
      await Future.delayed(const Duration(milliseconds: 200));
      await AppTrackingTransparency.requestTrackingAuthorization();
      logger.t('ATT requestTrackingAuthorization called.');
    } else {
      // 既に承認済み、拒否済み、制限済みの場合
      logger.t('ATT status is already: $status');
    }

    // AppsFlyerManagerの初期化と開始
    // ATTの承認を待った後に呼び出すことで、IDFAを確実に取得し、正確な計測を可能にする
    await _appsFlyerManager.initializeAndStartAfSdk(); // measurements.dart で修正したメソッド
    logger.t('AppsFlyerManager initialized and started.');
  }

  Future<void> _purchase(String id) async {
    logger.t('_purchase($id)');

    if (_purchases.products.isEmpty) {
      logger.t('products is empty');
      final state = _scaffoldKey.currentState;
      if (state != null) {
        state.showSnackBar(
          SnackBar(
            content: Text('button id: $id, products is empty'),
          ),
        );
      }
      return;
    }

    String btnLastThreeDigits = id.substring(id.length - 3);
    int btnIdIdx = int.parse(btnLastThreeDigits);
    Map<int, String> idMap = {
      1: 'jp.pygmyslabo.derbyleague.100',
      2: 'jp.pygmyslabo.derbyleague.500',
      3: 'jp.pygmyslabo.derbyleague.1500',
      4: 'jp.pygmyslabo.derbyleague.3000',
      5: 'jp.pygmyslabo.derbyleague.5000',
      6: 'jp.pygmyslabo.derbyleague.10000',
    };

    String productId = idMap[btnIdIdx]!;
    logger.t('productId: $productId');

    var product =
        _purchases.products.firstWhere((element) => element.id == productId);

    final result = await _purchases.buy(product);
    // resultとidをSnackBarで表示
    final message = 'productId: $productId, result: $result';
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> _restore() async {
    await _purchases.restore();
  }

  @override
  void initState() {
    super.initState();

    // ATTの初期化とAppsFlyer SDKの開始を非同期で実行
    // これをinitStateの最初の方に配置することで、アプリ起動後速やかに処理が開始される
    _initATTAndAppsFlyer();

    // WebViewの初期化は既存のままでOK
    _controller = WebViewController()
      ..loadRequest(Uri.parse('https://derby-league.com/dl_app/Top/'))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            logger.t('progress: $progress');
          },
          onPageStarted: (String url) {
            logger.t('page started: $url');
          },
          onPageFinished: (String url) {
            logger.t('page finished: $url');
            if (url == 'https://derby-league.com/dl_app/Payment/') {
              injectJavascript(_controller);
            }

            sendAppFlyerEvent(url);
          },
          onWebResourceError: (WebResourceError error) {
            logger.e('web resource error: $error');
          },
          onNavigationRequest: (NavigationRequest request) {
            logger.t('navigation request: $request');
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'flutterChannel',
        onMessageReceived: (message) async {
          logger.t('message: ${message.message}');
          final id = message.message;
          setState(() {
            _isProcessing = true;
          });

          await _purchase(id);
          setState(() {
            _isProcessing = false;
          });
        },
      );
    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    // 購入履歴の復元処理は、AppsFlyerの初期化とは直接関係ないため、この位置で問題ありません。
    // _isProcessing の状態管理はアプリのUXに合わせて調整してください。
    () async {
      await _restore();
      setState(() {
        _isProcessing = false;
      });
    }();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldKey,
      child: Scaffold(
        // デバッグ用設定ボタン(歯車アイコン)
        // TODO: 本番リリース時には削除してください
        floatingActionButton: debug
            ? FloatingActionButton(
                onPressed: () {
                  showDialog<void>(
                      context: context,
                      builder: (_) {
                        return _appsFlyerManager.buildMeasurementButtons();
                      });
                },
                child: const Icon(Icons.settings),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: _isProcessing
                      ? [
                          // 処理中
                          WebViewWidget(
                            controller: _controller,
                          ),
                          const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ]
                      : [
                          // 通常
                          WebViewWidget(
                            controller: _controller,
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

