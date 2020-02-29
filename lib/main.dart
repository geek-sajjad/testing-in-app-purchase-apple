import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  StreamSubscription<List<PurchaseDetails>> _subscription;
  final InAppPurchaseConnection _connection = InAppPurchaseConnection.instance;
  bool _isAvailble;
  bool _loading = true;
  List<ProductDetails> _products = [];
  String _queryProductError;
  bool _purchasePending = false;
  PurchaseVerificationData _purchaseVerificationData;

  @override
  void initState() {
    final Stream purchaseUpdates =
        InAppPurchaseConnection.instance.purchaseUpdatedStream;
    _subscription = purchaseUpdates.listen((purchases) {
      _listenToPurchaseUpdated(purchases);
    });
    initStoreInfo();
    super.initState();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> initStoreInfo() async {
    final bool isAvailable = await _connection.isAvailable();
    
    // await Future.delayed(Duration(seconds: 4));

    // final bool isAvailable = false;
    if (!isAvailable) {
      setState(() {
        _isAvailble = isAvailable;
        _loading = false;
      });
      return;
    }

    ProductDetailsResponse productDetailsResponse =
        await _connection.queryProductDetails(
            ['surf.vpn.one.month.premium', 'surf.vpn.three.month.premium', 'surf.vpn.twelve.month.premium'].toSet());

    if (productDetailsResponse.error != null) {
      // handle error
      _queryProductError = productDetailsResponse.error.message;
      print(productDetailsResponse.error.message);
      return;
    }

    if (productDetailsResponse.productDetails.isEmpty) {
      // handle error
      print("Products is eampty");
      return;
    }

    setState(() {
      _products = productDetailsResponse.productDetails;
      _loading = false;
      _isAvailble = isAvailable;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> stack = [];
    if (_queryProductError == null) {
      stack.add(ListView(
        children: <Widget>[
          _buildConnectionCheckTile(),
          _buildProductList(),
        ],
      ));
      // stack.addAll([
      //   _buildConnectionCheckTile(),
      //   _buildProductList(),
      // ]);
    } else {
      stack.addAll([
        Card(
          child: Text(_queryProductError),
        ),
      ]);
    }
    if (_purchasePending) {
      stack.add(
        Stack(
          children: [
            Opacity(
              opacity: 0.6,
              child: const ModalBarrier(dismissible: false, color: Colors.grey),
            ),
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Stack(
        children: stack,
      ),
    );
  }

  Card _buildProductList() {
    List<ListTile> productList = <ListTile>[];
    _products.forEach((product) {
      productList.add(
        ListTile(
          subtitle: Text(
            product.description,
          ),
          title: Text(product.title),
          trailing: FlatButton(
            color: Colors.green,
            child: Text(product.price),
            onPressed: () {
              // purcahse buy
              // _connection.buyConsumable(purchaseParam: null)
              PurchaseParam purchaseParam = PurchaseParam(
                productDetails: product,
                sandboxTesting: true,
                applicationUserName: null,
              );
              _connection.buyConsumable(
                purchaseParam: purchaseParam,
                autoConsume: true,
              );
            },
          ),
        ),
      );
    });
    return Card(
      child: Column(
        children: productList,
      ),
    );
  }

  Card _buildConnectionCheckTile() {
    if (_loading) {
      return Card(child: ListTile(title: const Text('Trying to connect...')));
    }
    final Widget storeHeader = ListTile(
      leading: Icon(_isAvailble ? Icons.check : Icons.block,
          color: _isAvailble ? Colors.green : Colors.red),
      title: Text(
          'The store is ' + (_isAvailble ? 'available' : 'unavailable') + '.'),
    );
    return Card(
      child: storeHeader,
    );
  }
  
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    
    purchaseDetailsList.forEach((PurchaseDetails purchaseDetails) async{
      if(purchaseDetails.status == PurchaseStatus.pending){
        // Handle Pending Status
        print("pending");
        showPendingUI();
      }else if(purchaseDetails.status == PurchaseStatus.error){
        // Handle Error
        handleError(purchaseDetails.error);        
      }else if(purchaseDetails.status == PurchaseStatus.purchased){
        setState(() {
          _purchasePending = false;
        });
        // Verify Purchase...
        print("purchased");
        bool valid = await _verifyPurchase(purchaseDetails);
        if(valid){
          // Deliver Product
          print("Deliver Product");
        }else{
          // handle invalid purchase
          print("Hanlde invalid purchase");
          return;
        }
      }

      if (purchaseDetails.pendingCompletePurchase) {
        print("Complited");
        BillingResultWrapper billingResultWrapper =  await _connection.completePurchase(purchaseDetails);
        print("billing result wrapper debug message : ${billingResultWrapper.debugMessage}");
        print("billing result wrapper response code : ${billingResultWrapper.responseCode}");
      }


    });
  }
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async{
    // IMPORTANT!! Always verify a purchase before delivering the product.
    // For the purpose of an example, we directly return true.
    print("verifying purchase");
    PurchaseVerificationData purchaseVerificationData = purchaseDetails.verificationData;
    if(purchaseVerificationData.source == IAPSource.AppStore){
      // use this for the verify purchase
      String verificationData = purchaseVerificationData.serverVerificationData;
      print("verification data : $verificationData");
      // return await _makeVerifyRequest(verificationData);
      return Future<bool>.value(true);
    }
    return false;
    
  }

  Future<bool> _makeVerifyRequest(String verificationData) async {
    const String url = 'https://sandbox.itunes.apple.com/verifyReceipt';
    Map body = {'receipt-data' : verificationData};

    var response  = await http.post(url, body: jsonEncode(body));
    print("this is the body : $body");
    if(response.statusCode == 200){
      print(response.body);
      return true;
    }
    return false;
  }

  void showPendingUI() {
    setState(() {
      _purchasePending = true;
    });
  }
  void handleError(IAPError error) {
    print("error : => ${error.message}");
    setState(() {
      _purchasePending = false;
    });
  }

}
