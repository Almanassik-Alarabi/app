import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: "camera; microphone",
    iframeAllowFullscreen: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
  );

  static const bool kDebugMode = true; // Set to false in release
  String onesignalPlayerId = "null";
  String savedAgencyId = "null";

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // Get OneSignal ID
    onesignalPlayerId = OneSignal.User.pushSubscription.id ?? "null";
    
    // Get Saved Agency ID
    final prefs = await SharedPreferences.getInstance();
    savedAgencyId = prefs.getString('agency_id') ?? "null";
    
    // Refresh WebView if controller exists to inject new values
    if (webViewController != null) {
      _injectVariables(webViewController!);
    }
    
    // Listen for OneSignal changes
    OneSignal.User.pushSubscription.addObserver((state) {
      if (state.current.id != null) {
        setState(() {
          onesignalPlayerId = state.current.id!;
        });
        if (webViewController != null) {
           webViewController!.evaluateJavascript(source: "window.onesignal_player_id = '$onesignalPlayerId';");
        }
      }
    });
  }

  void _injectVariables(InAppWebViewController controller) {
    controller.evaluateJavascript(source: """
        window.onesignal_player_id = '$onesignalPlayerId';
        window.saved_agency_id = '$savedAgencyId';
    """);
  }

  void _injectPolyfills(InAppWebViewController controller) {
    // Injects the AndroidInterface object to mimic the native Android app
    // We use callHandler for methods we want to handle in Flutter (async)
    // We return local variables for methods that need to be sync
    // window.flutter_inappwebview.callHandler is standard for this plugin
    String js = """
      window.AndroidInterface = {
        postMessage: function(message) {
           window.flutter_inappwebview.callHandler('postMessage', message);
        },
        getExternalId: function() {
           return window.onesignal_player_id || "null";
        },
        getSavedAgencyId: function() {
           return window.saved_agency_id || "null";
        },
        forceReLogin: function(agencyId) {
           window.flutter_inappwebview.callHandler('forceReLogin', agencyId);
        },
        testNotification: function() {
           window.flutter_inappwebview.callHandler('testNotification');
           return "Check Log";
        }
      };

      // ReactNativeWebView polyfill as seen in original app
      window.ReactNativeWebView = {
          postMessage: function(data) {
              window.AndroidInterface.postMessage(data);
          }
      };
    """;
    controller.evaluateJavascript(source: js);
  }

  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF003B39), // Match splash background
      body: SafeArea(
        child: Stack(
          children: [
            // 1. The WebView (Bottom Layer)
            InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(
                url: WebUri("https://www.almanassikalarabi.com/agencie/dashboard.html"),
              ),
              initialSettings: settings,
              onWebViewCreated: (controller) {
                webViewController = controller;
                
                // Register Handlers
                controller.addJavaScriptHandler(handlerName: 'postMessage', callback: (args) {
                  _handlePostMessage(args[0]);
                });
                
                controller.addJavaScriptHandler(handlerName: 'forceReLogin', callback: (args) {
                   _handleForceReLogin(args[0]);
                });
                
                controller.addJavaScriptHandler(handlerName: 'testNotification', callback: (args) {
                   _handleTestNotification();
                });
              },
              onLoadStart: (controller, url) {
                _injectVariables(controller);
                _injectPolyfills(controller);
              },
              onLoadStop: (controller, url) async {
                _injectVariables(controller);
                _injectPolyfills(controller);
                // Simple delay to ensure rendering has started before removing cover
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                 return NavigationActionPolicy.ALLOW;
              },
              onConsoleMessage: (controller, consoleMessage) {
                if (kDebugMode) {
                  print("WebView Console: ${consoleMessage.message}");
                }
              },
            ),

            // 2. The Loading Overlay (Top Layer) matches SplashScreen exactly
            // We use AnimatedOpacity for a smooth fade-out effect.
            IgnorePointer(
              ignoring: !_isLoading, // Allow touches to pass through when not loading
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 800),
                opacity: _isLoading ? 1.0 : 0.0,
                curve: Curves.easeInOut,
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF003B39), 
                        Color(0xFF00554C), 
                        Color(0xFFC5A028), 
                        Color(0xFFD4AF37), 
                      ],
                      stops: [0.0, 0.45, 0.8, 1.0],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      
                      // Static Logo (No entrances, just sits there)
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(35),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                              blurRadius: 50,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(35),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 140,
                            height: 140,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 60),
                      
                      // Static Welcome Message
                      const Column(
                        children: [
                          Text(
                            'مرحباً بكم',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'Cairo', 
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(
                                  blurRadius: 10.0,
                                  color: Colors.black38,
                                  offset: Offset(2.0, 2.0),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'في تطبيق',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white70,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 15),
                      
                      // Static App Name
                      const Text(
                        'المناسك العربي',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFFD700), // Brighter Gold
                          fontFamily: 'Cairo',
                          letterSpacing: 1.5,
                          shadows: [
                             Shadow(
                              blurRadius: 8.0,
                              color: Colors.black45,
                              offset: Offset(2.0, 2.0),
                            ),
                          ],
                        ),
                      ),
                      
                      const Spacer(flex: 4),
                      
                      // Static Loading Indicator
                      Column(
                        children: const [
                          CircularProgressIndicator(
                            color: Color(0xFFFFD700),
                            strokeWidth: 2,
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Almanassik Alarabi',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white54,
                              letterSpacing: 2.0,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePostMessage(dynamic message) async {
    try {
      print("Received message: $message");
      Map<String, dynamic> json;
      if (message is String) {
        json = jsonDecode(message);
      } else {
        json = Map<String, dynamic>.from(message);
      }

      String? type = json['type'];
      
      if (type == "LOGIN_SUCCESS") {
        var payload = json['payload'];
        String? agencyId = payload['agencyId'];
        if (agencyId == null || agencyId.isEmpty) {
           var agency = payload['agency'];
           if (agency != null) {
             agencyId = agency['id'];
           }
        }
        
        String? onesignalId = payload['onesignalPlayerId'];
        
        if (agencyId != null && agencyId.isNotEmpty) {
          // Login OneSignal
          OneSignal.login(agencyId);
          print("OneSignal Login called for: $agencyId");
          
          // Save to Prefs
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('agency_id', agencyId);
          if (onesignalId != null) await prefs.setString('onesignal_player_id', onesignalId);
          
          // Update local var for JS
          savedAgencyId = agencyId;
          if (webViewController != null) {
            webViewController!.evaluateJavascript(source: "window.saved_agency_id = '$agencyId';");
          }
        }
      }
    } catch (e) {
      print("Error parsing message: $e");
    }
  }

  void _handleForceReLogin(dynamic agencyId) {
    if (agencyId is String) {
      print("Force Re-Login for: $agencyId");
      OneSignal.logout();
      
      Future.delayed(const Duration(seconds: 1), () async {
        OneSignal.login(agencyId);
        print("Re-login successful");
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('agency_id', agencyId);
        savedAgencyId = agencyId;
        if (webViewController != null) {
            webViewController!.evaluateJavascript(source: "window.saved_agency_id = '$agencyId';");
        }
      });
    }
  }

  void _handleTestNotification() {
    var id = OneSignal.User.pushSubscription.id;
    var optedIn = OneSignal.User.pushSubscription.optedIn;
    print("Test Notification Status: ID=$id, Subscribed=$optedIn");
  }
}
