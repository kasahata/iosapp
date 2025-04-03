import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:project/globals.dart';

// #docregion platform_imports
// Import for Android features.
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
// Import for iOS features.
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

enum StoreState {
  loading,
  available,
  notAvailable,
}

enum ProductStatus {
  purchasable,
  purchased,
  pending,
}

class PurchasableProduct {
  String get id => productDetails.id;
  String get title => productDetails.title;
  String get description => productDetails.description;
  String get price => productDetails.price;
  ProductStatus status;
  ProductDetails productDetails;

  PurchasableProduct(this.productDetails) : status = ProductStatus.purchasable;
}

class IAPConnection {
  static InAppPurchase? _instance;
  static set instance(InAppPurchase value) {
    _instance = value;
  }

  static InAppPurchase get instance {
    _instance ??= InAppPurchase.instance;
    return _instance!;
  }
}

class Purchases extends ChangeNotifier {
  StoreState storeState = StoreState.loading;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<PurchasableProduct> products = [];

  bool get purchasePending => _purchasePending;
  bool _purchasePending = false;

  final iapConnection = IAPConnection.instance;

  String paymentType = '';
  String paymentId = '';
  int userId = -1;

  Purchases() {
    logger.t('Purchases()');
    final purchaseUpdated = iapConnection.purchaseStream;
    _subscription = purchaseUpdated.listen(
      (List<PurchaseDetails> purchaseDetailsList) {
        _onPurchaseUpdate(purchaseDetailsList);
      },
      onDone: _updateStreamOnDone,
      onError: _updateStreamOnError,
    );
    loadPurchases();
  }

  Future<void> loadPurchases() async {
    logger.t('loadPurchases()');
    final available = await iapConnection.isAvailable();
    if (!available) {
      storeState = StoreState.notAvailable;
      notifyListeners();
      logger.e('IAP is not available on this device');
      return;
    }
    // TODO: プラットフォームで同じIDだと確定したら分岐しない
    Set<String> ids = Platform.isIOS
        ? {
            'jp.pygmyslabo.derbyleague.100',
            'jp.pygmyslabo.derbyleague.500',
            'jp.pygmyslabo.derbyleague.1500',
            'jp.pygmyslabo.derbyleague.3000',
            'jp.pygmyslabo.derbyleague.5000',
            'jp.pygmyslabo.derbyleague.10000',
          }
        : {
            'jp.pygmyslabo.derbyleague.100',
            'jp.pygmyslabo.derbyleague.500',
            'jp.pygmyslabo.derbyleague.1500',
            'jp.pygmyslabo.derbyleague.3000',
            'jp.pygmyslabo.derbyleague.5000',
            'jp.pygmyslabo.derbyleague.10000',
          }.toSet();
    final response = await iapConnection.queryProductDetails(ids);
    logger.t(
        'loadPurchases() response.productDetails: ${response.productDetails}');
    products =
        response.productDetails.map((e) => PurchasableProduct(e)).toList();
    logger.t('loadPurchases() products: $products');
    storeState = StoreState.available;
    notifyListeners();
  }

  @override
  void dispose() {
    logger.t('dispose()');
    _subscription.cancel();
    super.dispose();
  }

  Future<void> restore() async {
    logger.t('restore()');
    await iapConnection.restorePurchases();
  }

  Future<bool> buy(PurchasableProduct product) async {
    logger.t('buy()');

    //iOSでの同一商品購入時エラー対策
    if (Platform.isIOS) {
      var paymentWrapper = SKPaymentQueueWrapper();
      var transactions = await paymentWrapper.transactions();
      for (SKPaymentTransactionWrapper transaction in transactions) {
        await paymentWrapper.finishTransaction(transaction);
      }
    }

    final purchaseParam = PurchaseParam(productDetails: product.productDetails);
    final result =
        await iapConnection.buyConsumable(purchaseParam: purchaseParam);
    logger.t('buy() result: $result');
    return result;
  }

  Future<void> _onPurchaseUpdate(
      List<PurchaseDetails> purchaseDetailsList) async {
    logger.t('_onPurchaseUpdate()');
    logger.t('purchaseDetailsList: $purchaseDetailsList');
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _showPendingUI();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          _handleError(purchaseDetails.error!);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          final bool valid = await _verifyPurchase(purchaseDetails);
          if (valid) {
            unawaited(_unlockContents(purchaseDetails));
          } else {
            _handleInvalidPurchase(purchaseDetails);
            return;
          }
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await iapConnection.completePurchase(purchaseDetails);
        }
      }
    }
    notifyListeners();
  }

  // レシート検証
  // PurchaseDetailsからlocalVerificationDataを取得し、ローカルで検証する
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    logger.t('_verifyPurchase() purchaseDetails: $purchaseDetails');
    var localVerificationData = '';
    Map<String, dynamic> receipt = {};
    if (Platform.isIOS) {
      var receiptBody = {
        'receipt-data': purchaseDetails.verificationData.localVerificationData,
        'exclude-old-transactions': false,
        'password': '94131d9ae81c4c018203da8e815cfae0'
      };
      var response = await validateReceiptIos(receiptBody);
      localVerificationData = response.body;
      receipt = ResponseBody.fromJson(jsonDecode(localVerificationData))
          .receipt
          .inApp
          .toJson();
    } else {
      GooglePlayPurchaseDetails googlePlayPurchaseDetails =
          purchaseDetails as GooglePlayPurchaseDetails;
      localVerificationData =
          googlePlayPurchaseDetails.verificationData.localVerificationData;
      logger.t("localVerificationData : $localVerificationData");
      receipt = jsonDecode(localVerificationData);
    }
    clearPaymentData();
    if (Platform.isIOS) {
      if (iosReceiptCheck(receipt) == false) {
        return Future<bool>.value(false);
      }
      logger.t("receipt:$receipt");

      paymentType = receipt['product_id'];
      paymentId = receipt['transaction_id'];
    } else {
      logger.t("receipt:$receipt");

      if (androidReceiptNullCheck(receipt) == false) {
        return Future<bool>.value(false);
      }

      if (receipt['purchaseState'] != 0) {
        return Future<bool>.value(false);
      }

      paymentType = receipt['productId'];
      paymentId = receipt['orderId'];
    }

    return Future<bool>.value(true);
  }

  void clearPaymentData() {
    paymentType = '';
    paymentId = '';
  }

  //iOSのレシート検証API呼び出し
  Future<http.Response> validateReceiptIos(receiptBody) async {
    const String url = debug
        ? 'https://sandbox.itunes.apple.com/verifyReceipt'
        : 'https://buy.itunes.apple.com/verifyReceipt';
    return await http.post(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: json.encode(receiptBody),
    );
  }

  // iOSのレシートのチェック
  bool iosReceiptCheck(Map<String, dynamic> receipt) {
    if (receipt.isEmpty) {
      logger.t('receipt is empty');
      return false;
    } else {
      logger.t(receipt);
    }

    if (receipt['product_id'] == null || receipt['product_id'] == '') {
      logger.t("product_id is empty");
      return false;
    }

    if (receipt['transaction_id'] == null || receipt['transaction_id'] == '') {
      logger.t("transaction_id is empty");
      return false;
    }

    return true;
  }

  // AndroidのレシートのNullチェック
  bool androidReceiptNullCheck(Map<String, dynamic> receipt) {
    if (receipt['orderId'] == null) {
      return false;
    }

    if (receipt['purchaseToken'] == null) {
      return false;
    }

    if (receipt['productId'] == null) {
      return false;
    }

    if (receipt['purchaseTime'] == null) {
      return false;
    }

    if (receipt['purchaseState'] == null) {
      return false;
    }

    return true;
  }

  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    logger.t('_handleInvalidPurchase() purchaseDetails: $purchaseDetails');
    // handle invalid purchase here if  _verifyPurchase` failed.
    _purchasePending = false;
  }

  void _handleError(IAPError error) {
    logger.e('_handleError() error: $error');
    _purchasePending = false;
  }

  // 購入が完了したので、サーバーに通知してコンテンツを解放する
  Future<void> _unlockContents(PurchaseDetails purchaseDetails) async {
    logger.t('_unlockContents()');
    if (purchaseDetails.status == PurchaseStatus.purchased) {
      logger.t('purchaseDetails.status == PurchaseStatus.purchased');
      await _getUserId();
      await _request();
    }

    if (purchaseDetails.pendingCompletePurchase) {
      logger.t('purchaseDetails.pendingCompletePurchase');
      await iapConnection.completePurchase(purchaseDetails);
    }

    _purchasePending = false;
  }

  void _showPendingUI() {
    logger.t('_showPendingUI()');
    _purchasePending = true;
  }

  void _updateStreamOnDone() {
    logger.t('_updateStreamOnDone()');
    _subscription.cancel();
  }

  void _updateStreamOnError(dynamic error) {
    logger.e('_updateStreamOnError() error: $error');
    //Handle error here
  }

  Future<void> _getUserId() async {
    logger.t('_getUserId()');

    final response = await http
        .get(Uri.parse('https://derby-league.com/dl_app/Top/before_p'));
    final jsonResponse = jsonDecode(response.body);
    userId = jsonResponse['user_id'];
  }

  Future<void> _request() async {
    logger.t('_request()');

    if (paymentType == '' || userId == -1 || paymentId == '') {
      String message = '';
      message += paymentType == ''
          ? 'paymentType is empty\n'
          : 'paymentType : $paymentType\n';
      message += userId == -1 ? 'userId is empty\n' : 'userId : $userId\n';
      message +=
          paymentId == '' ? 'paymentId is empty' : 'paymentId : $paymentId';
      logger.t(message);
      clearPaymentData();
      return;
    }

    String message = '';
    message += 'paymentType : $paymentType\n';
    message += 'userId : $userId\n';
    message += 'paymentId : $paymentId';
    logger.t(message);

    Uri url = debug
        ? Uri.parse("https://derby-league.com/dl_app_dev/Payment/payment_end")
        : Uri.parse("https://derby-league.com/dl_app/Payment/payment_end");
    Map<String, String> headers = {'content-type': 'application/json'};
    String body = json.encode({
      'payment_type': paymentType,
      'user_id': userId,
      'payment_id': paymentId
    });

    http.Response resp = await http.post(url, headers: headers, body: body);

    clearPaymentData();

    if (resp.statusCode != 200) {
      return;
    }
  }
}

//iOSのレシート用クラス
class ResponseBody {
  String environment;
  bool isRetryable;
  String latestReceipt;
  List<dynamic> latestReceiptInfo;
  String pendingRenewalInfo;
  Receipt receipt;
  int status;

  ResponseBody({
    required this.environment,
    required this.isRetryable,
    required this.latestReceipt,
    required this.latestReceiptInfo,
    required this.pendingRenewalInfo,
    required this.receipt,
    required this.status,
  });

  factory ResponseBody.fromJson(Map<String, dynamic> json) => ResponseBody(
        environment: json["environment"] ?? "",
        isRetryable: json["is_retryable"] ?? false,
        latestReceipt: json["latest_receipt"] ?? "",
        latestReceiptInfo: json["latest_receipt_info"] ?? {},
        pendingRenewalInfo: json["pending_renewal_info"] ?? "",
        receipt: (json["receipt"] != null)
            ? Receipt.fromJson(json["receipt"])
            : Receipt(
                adamId: -1,
                appItemId: -1,
                applicationVersion: "",
                bundleId: "",
                downloadId: -1,
                expirationDate: "",
                expirationDateMs: "",
                expirationDatePst: "",
                inApp: InApp(
                    cancellationDate: "",
                    cancellationDateMs: "",
                    cancellationDatePst: "",
                    cancellationReason: "",
                    expiresDate: "",
                    expiresDateMs: "",
                    expiresDatePst: "",
                    isInIntroOfferPeriod: "",
                    isTrialPeriod: "",
                    originalPurchaseDate: "",
                    originalPurchaseDateMs: "",
                    originalPurchaseDatePst: "",
                    originalTransactionId: "",
                    productId: "",
                    promotionalOfferId: "",
                    purchaseDate: "",
                    purchaseDateMs: "",
                    purchaseDatePst: "",
                    quantity: "",
                    transactionId: "",
                    webOrderLineItemId: ""),
                originalApplicationVersion: "",
                originalPurchaseDate: "",
                originalPurchaseDateMs: "",
                originalPurchaseDatePst: "",
                preorderDate: "",
                preorderDateMs: "",
                preorderDatePst: "",
                receiptCreationDate: "",
                receiptCreationDateMs: "",
                receiptCreationDatePst: "",
                receiptType: "",
                requestDate: "",
                requestDateMs: "",
                requestDatePst: "",
                versionExternalIdentifier: -1),
        status: json["status"] ?? -1,
      );
}

class Receipt {
  int adamId;
  int appItemId;
  String applicationVersion;
  String bundleId;
  int downloadId;
  String expirationDate;
  String expirationDateMs;
  String expirationDatePst;
  InApp inApp;
  String originalApplicationVersion;
  String originalPurchaseDate;
  String originalPurchaseDateMs;
  String originalPurchaseDatePst;
  String preorderDate;
  String preorderDateMs;
  String preorderDatePst;
  String receiptCreationDate;
  String receiptCreationDateMs;
  String receiptCreationDatePst;
  String receiptType;
  String requestDate;
  String requestDateMs;
  String requestDatePst;
  int versionExternalIdentifier;

  Receipt({
    required this.adamId,
    required this.appItemId,
    required this.applicationVersion,
    required this.bundleId,
    required this.downloadId,
    required this.expirationDate,
    required this.expirationDateMs,
    required this.expirationDatePst,
    required this.inApp,
    required this.originalApplicationVersion,
    required this.originalPurchaseDate,
    required this.originalPurchaseDateMs,
    required this.originalPurchaseDatePst,
    required this.preorderDate,
    required this.preorderDateMs,
    required this.preorderDatePst,
    required this.receiptCreationDate,
    required this.receiptCreationDateMs,
    required this.receiptCreationDatePst,
    required this.receiptType,
    required this.requestDate,
    required this.requestDateMs,
    required this.requestDatePst,
    required this.versionExternalIdentifier,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
      adamId: json["adam_id"] ?? 0,
      appItemId: json["app_item_id"] ?? 0,
      applicationVersion: json["application_version"] ?? "",
      bundleId: json["bundle_id"] ?? "",
      downloadId: json["download_id"] ?? 0,
      expirationDate: json["expiration_date"] ?? "",
      expirationDateMs: json["expiration_date_ms"] ?? "",
      expirationDatePst: json["expiration_date_pst"] ?? "",
      inApp: InApp.fromJson(json["in_app"][0]),
      originalApplicationVersion: json["original_application_version"] ?? "",
      originalPurchaseDate: json["original_purchase_date"] ?? "",
      originalPurchaseDateMs: json["original_purchase_date_ms"] ?? "",
      originalPurchaseDatePst: json["original_purchase_date_pst"] ?? "",
      preorderDate: json["preorder_date"] ?? "",
      preorderDateMs: json["preorder_date_ms"] ?? "",
      preorderDatePst: json["preorder_date_pst"] ?? "",
      receiptCreationDate: json["receipt_creation_date"] ?? "",
      receiptCreationDateMs: json["receipt_creation_date_ms"] ?? "",
      receiptCreationDatePst: json["receipt_creation_date_pst"] ?? "",
      receiptType: json["receipt_type"] ?? "",
      requestDate: json["request_date"] ?? "",
      requestDateMs: json["request_date_ms"] ?? "",
      requestDatePst: json["request_date_pst"] ?? "",
      versionExternalIdentifier: json["version_external_identifier"] ?? 0);
}

class InApp {
  String cancellationDate;
  String cancellationDateMs;
  String cancellationDatePst;
  String cancellationReason;
  String expiresDate;
  String expiresDateMs;
  String expiresDatePst;
  String isInIntroOfferPeriod;
  String isTrialPeriod;
  String originalPurchaseDate;
  String originalPurchaseDateMs;
  String originalPurchaseDatePst;
  String originalTransactionId;
  String productId;
  String promotionalOfferId;
  String purchaseDate;
  String purchaseDateMs;
  String purchaseDatePst;
  String quantity;
  String transactionId;
  String webOrderLineItemId;

  InApp({
    required this.cancellationDate,
    required this.cancellationDateMs,
    required this.cancellationDatePst,
    required this.cancellationReason,
    required this.expiresDate,
    required this.expiresDateMs,
    required this.expiresDatePst,
    required this.isInIntroOfferPeriod,
    required this.isTrialPeriod,
    required this.originalPurchaseDate,
    required this.originalPurchaseDateMs,
    required this.originalPurchaseDatePst,
    required this.originalTransactionId,
    required this.productId,
    required this.promotionalOfferId,
    required this.purchaseDate,
    required this.purchaseDateMs,
    required this.purchaseDatePst,
    required this.quantity,
    required this.transactionId,
    required this.webOrderLineItemId,
  });

  factory InApp.fromJson(Map<String, dynamic> json) => InApp(
      cancellationDate: json["cancellation_date"] ?? "",
      cancellationDateMs: json["cancellation_date_ms"] ?? "",
      cancellationDatePst: json["cancellation_date_pst"] ?? "",
      cancellationReason: json["cancellation_reason"] ?? "",
      expiresDate: json["expires_date"] ?? "",
      expiresDateMs: json["expires_date_ms"] ?? "",
      expiresDatePst: json["expires_date_pst"] ?? "",
      isInIntroOfferPeriod: json["is_in_intro_offer_period"] ?? "",
      isTrialPeriod: json["is_trial_period"] ?? "",
      originalPurchaseDate: json["original_purchase_date"] ?? "",
      originalPurchaseDateMs: json["original_purchase_date_ms"] ?? "",
      originalPurchaseDatePst: json["original_purchase_date_pst"] ?? "",
      originalTransactionId: json["original_transaction_id"] ?? "",
      productId: json["product_id"] ?? "",
      promotionalOfferId: json["promotional_offer_id"] ?? "",
      purchaseDate: json["purchase_date"] ?? "",
      purchaseDateMs: json["purchase_date_ms"] ?? "",
      purchaseDatePst: json["purchase_date_pst"] ?? "",
      quantity: json["quantity"] ?? "",
      transactionId: json["transaction_id"] ?? "",
      webOrderLineItemId: json["web_order_line_item_id"] ?? "");

  Map<String, dynamic> toJson() => {
        "cancellation_date": cancellationDate,
        "cancellation_date_ms": cancellationDateMs,
        "cancellation_date_pst": cancellationDatePst,
        "cancellation_reason": cancellationReason,
        "expires_date": expiresDate,
        "expires_date_ms": expiresDateMs,
        "expires_date_pst": expiresDatePst,
        "is_in_intro_offer_period": isInIntroOfferPeriod,
        "is_trial_period": isTrialPeriod,
        "original_purchase_date": originalPurchaseDate,
        "original_purchase_date_ms": originalPurchaseDateMs,
        "original_purchase_date_pst": originalPurchaseDatePst,
        "original_transaction_id": originalTransactionId,
        "product_id": productId,
        "promotional_offer_id": promotionalOfferId,
        "purchase_date": purchaseDate,
        "purchase_date_ms": purchaseDateMs,
        "purchase_date_pst": purchaseDatePst,
        "quantity": quantity,
        "transaction_id": transactionId,
        "web_order_line_item_id": webOrderLineItemId,
      };
}
