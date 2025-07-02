import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

class GiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Gift types with online Lottie animations URLs that work with Lottie.network()
  final List<Map<String, dynamic>> giftTypes = [
    {
      'id': 1,
      'name': 'Rose',
      'cost': 10,
      'animationAsset':
          'https://assets2.lottiefiles.com/packages/lf20_8wREpI.json',
      'duration': Duration(seconds: 2),
    },
    {
      'id': 2,
      'name': 'Heart',
      'cost': 20,
      'animationAsset':
          'https://assets1.lottiefiles.com/packages/lf20_kc9q7k31.json',
      'duration': Duration(seconds: 2),
    },
    {
      'id': 3,
      'name': 'Diamond',
      'cost': 50,
      'animationAsset':
          'https://assets4.lottiefiles.com/packages/lf20_t9gkkhz4.json',
      'duration': Duration(seconds: 2),
    },
    {
      'id': 4,
      'name': 'Crown',
      'cost': 100,
      'animationAsset':
          'https://assets8.lottiefiles.com/packages/lf20_xyadoh9h.json',
      'duration': Duration(seconds: 2),
    },
    {
      'id': 5,
      'name': 'Gift Box',
      'cost': 200,
      'animationAsset':
          'https://assets1.lottiefiles.com/packages/lf20_25ulrdkh.json',
      'duration': Duration(seconds: 3),
    },
    {
      'id': 6,
      'name': 'Balloons',
      'cost': 500,
      'animationAsset':
          'https://assets6.lottiefiles.com/packages/lf20_poqmiqvs.json',
      'duration': Duration(seconds: 3),
    },
    {
      'id': 7,
      'name': 'Celebration',
      'cost': 1000,
      'animationAsset':
          'https://assets3.lottiefiles.com/packages/lf20_obhph3sh.json',
      'duration': Duration(seconds: 3),
    },
    {
      'id': 8,
      'name': 'Airplane',
      'cost': 2000,
      'animationAsset':
          'https://assets1.lottiefiles.com/packages/lf20_jcikwtux.json',
      'duration': Duration(seconds: 3),
    },
    {
      'id': 9,
      'name': 'Valentine Heart',
      'cost': 30,
      'animationAsset':
          'https://assets5.lottiefiles.com/packages/lf20_fcfjwiyb.json',
      'duration': Duration(seconds: 2),
    },
    {
      'id': 10,
      'name': 'Star',
      'cost': 40,
      'animationAsset':
          'https://assets2.lottiefiles.com/packages/lf20_AiTnw2.json',
      'duration': Duration(seconds: 2),
    },
    {
      'id': 11,
      'name': 'Trophy',
      'cost': 50,
      'animationAsset':
          'https://assets7.lottiefiles.com/packages/lf20_touohxv0.json',
      'duration': Duration(seconds: 2),
    },
    {
      'id': 12,
      'name': 'Ring',
      'cost': 100,
      'animationAsset':
          'https://assets10.lottiefiles.com/packages/lf20_DMgKk1.json',
      'duration': Duration(seconds: 2),
    },
  ];

  // Get gift details by ID
  Map<String, dynamic> getGiftById(int giftId) {
    return giftTypes.firstWhere(
      (gift) => gift['id'] == giftId,
      orElse:
          () => {
            'id': 0,
            'name': 'Unknown',
            'cost': 0,
            'animationAsset': 'assets/animations/error.json',
            'duration': Duration(seconds: 2),
          },
    );
  }

  // Send a gift (unchanged logic)
  Future<Map<String, dynamic>> sendGift({
    required String liveId,
    required String hostId,
    required String userId,
    required String userName,
    required int giftId,
    required int giftCount,
    String? senderProfileUrl,
  }) async {
    final giftData = getGiftById(giftId);
    final totalCost = giftData['cost'] * giftCount;

    final walletDoc = await _firestore.collection('wallets').doc(userId).get();
    final userCoins = walletDoc.data()?['coins'] ?? 0;

    if (userCoins < totalCost) {
      return {
        'success': false,
        'message': 'Not enough coins',
        'coins': userCoins,
      };
    }

    await _firestore.collection('wallets').doc(userId).update({
      'coins': FieldValue.increment(-totalCost),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('wallets').doc(hostId).set({
      'coins': FieldValue.increment(totalCost),
      'userId': hostId,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore
        .collection('live_streams')
        .doc(liveId)
        .collection('gifts')
        .add({
          'giftId': giftId,
          'giftName': giftData['name'],
          'giftCount': giftCount,
          'totalCost': totalCost,
          'senderId': userId,
          'senderName': userName,
          'senderProfileUrl': senderProfileUrl,
          'receiverId': hostId,
          'timestamp': FieldValue.serverTimestamp(),
        });

    final updatedWalletDoc =
        await _firestore.collection('wallets').doc(userId).get();
    final updatedCoins = updatedWalletDoc.data()?['coins'] ?? 0;

    return {
      'success': true,
      'message': 'Gift sent successfully',
      'coins': updatedCoins,
    };
  }

  // Recharge user coins (unchanged logic)
  Future<Map<String, dynamic>> rechargeCoins({
    required String userId,
    required int amount,
  }) async {
    try {
      await _firestore.collection('wallets').doc(userId).set({
        'coins': FieldValue.increment(amount),
        'userId': userId,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore.collection('transactions').add({
        'userId': userId,
        'amount': amount,
        'type': 'recharge',
        'status': 'completed',
        'paymentMethod': 'demo',
        'timestamp': FieldValue.serverTimestamp(),
      });

      final walletDoc =
          await _firestore.collection('wallets').doc(userId).get();
      final updatedCoins = walletDoc.data()?['coins'] ?? 0;

      return {
        'success': true,
        'message': 'Coins recharged successfully',
        'coins': updatedCoins,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error recharging coins: $e'};
    }
  }

  void showGiftAnimation({
    required BuildContext context,
    required Map<String, dynamic> giftData,
  }) {
    final giftId = giftData['giftId'] ?? 1;
    final giftCount = giftData['giftCount'] ?? 1;
    final senderName = giftData['senderName'] ?? 'Someone';
    final senderProfileUrl = giftData['senderProfileUrl'];

    final gift = getGiftById(giftId);
    final animationDuration = Duration(milliseconds: 800);
    final displayDuration = Duration(seconds: 5);
    final slideOutDuration = Duration(milliseconds: 600);

    // Enhanced haptic feedback
    HapticFeedback.heavyImpact();

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder:
          (context) => TweenAnimationBuilder<Offset>(
            duration: animationDuration,
            tween: Tween<Offset>(
              begin: Offset(1.2, 0.0), // Start from right edge
              end: Offset(0.0, 0.0), // End at normal position
            ),
            curve: Curves.elasticOut,
            builder: (context, slideOffset, child) {
              return TweenAnimationBuilder<double>(
                duration: animationDuration,
                tween: Tween<double>(begin: 0.8, end: 1.0),
                curve: Curves.elasticOut,
                builder: (context, scale, child) {
                  return TweenAnimationBuilder<double>(
                    duration: Duration(milliseconds: 400),
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    curve: Curves.easeInOut,
                    builder: (context, opacity, child) {
                      return Positioned(
                        bottom: MediaQuery.of(context).size.height * 0.35,
                        left: 16,
                        right: 16,
                        child: Transform.translate(
                          offset: Offset(
                            slideOffset.dx * MediaQuery.of(context).size.width,
                            0,
                          ),
                          child: Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: opacity,
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  margin: EdgeInsets.only(
                                    left:
                                        MediaQuery.of(context).size.width * 0.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.purple.withOpacity(0.9),
                                        Colors.pink.withOpacity(0.9),
                                        Colors.orange.withOpacity(0.9),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 15,
                                        offset: Offset(0, 8),
                                      ),
                                      BoxShadow(
                                        color: Colors.purple.withOpacity(0.4),
                                        blurRadius: 20,
                                        offset: Offset(0, 0),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Animated gift icon
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withOpacity(0.2),
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Lottie.network(
                                          gift['animationAsset'],
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.contain,
                                          repeat: true,
                                        ),
                                      ),
                                      SizedBox(width: 12),

                                      // Gift info column
                                      Flexible(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Sender info row
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (senderProfileUrl !=
                                                    null) ...[
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: CircleAvatar(
                                                      backgroundImage:
                                                          NetworkImage(
                                                            senderProfileUrl,
                                                          ),
                                                      radius: 14,
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                ],
                                                Flexible(
                                                  child: Text(
                                                    senderName,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                      shadows: [
                                                        Shadow(
                                                          offset: Offset(1, 1),
                                                          blurRadius: 3,
                                                          color: Colors.black
                                                              .withOpacity(0.5),
                                                        ),
                                                      ],
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 4),

                                            // Gift details
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withOpacity(0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${giftCount}x',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    gift['name'],
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withOpacity(0.9),
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      SizedBox(width: 8),

                                      // Rotating sparkle effect
                                      RotationTransition(
                                        turns: AlwaysStoppedAnimation(0.0),
                                        child: TweenAnimationBuilder<double>(
                                          duration: Duration(seconds: 2),
                                          tween: Tween<double>(
                                            begin: 0,
                                            end: 1,
                                          ),
                                          builder: (context, value, child) {
                                            return Transform.rotate(
                                              angle: value * 2 * 3.14159,
                                              child: Icon(
                                                Icons.auto_awesome,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            );
                                          },
                                          onEnd: () {
                                            // This will continuously restart the animation
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
    );

    // Show the overlay
    Overlay.of(context).insert(overlayEntry);

    // Remove after display duration with slide-out effect
    Future.delayed(displayDuration, () {
      // Create slide-out animation
      OverlayEntry slideOutOverlay = OverlayEntry(
        builder:
            (context) => TweenAnimationBuilder<Offset>(
              duration: slideOutDuration,
              tween: Tween<Offset>(
                begin: Offset(0.0, 0.0),
                end: Offset(1.2, 0.0), // Slide out to right
              ),
              curve: Curves.easeInBack,
              builder: (context, slideOffset, child) {
                return TweenAnimationBuilder<double>(
                  duration: slideOutDuration,
                  tween: Tween<double>(begin: 1.0, end: 0.0),
                  curve: Curves.easeInOut,
                  builder: (context, opacity, child) {
                    return Positioned(
                      bottom: MediaQuery.of(context).size.height * 0.35,
                      left: 16,
                      right: 16,
                      child: Transform.translate(
                        offset: Offset(
                          slideOffset.dx * MediaQuery.of(context).size.width,
                          0,
                        ),
                        child: Opacity(
                          opacity: opacity,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              margin: EdgeInsets.only(
                                left: MediaQuery.of(context).size.width * 0.5,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.purple.withOpacity(0.9),
                                    Colors.pink.withOpacity(0.9),
                                    Colors.orange.withOpacity(0.9),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withOpacity(0.2),
                                    ),
                                    padding: EdgeInsets.all(8),
                                    child: Lottie.asset(
                                      gift['animationAsset'],
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.contain,
                                      repeat: true,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Flexible(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (senderProfileUrl != null) ...[
                                              Container(
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: CircleAvatar(
                                                  backgroundImage: NetworkImage(
                                                    senderProfileUrl,
                                                  ),
                                                  radius: 14,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                            ],
                                            Flexible(
                                              child: Text(
                                                senderName,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  shadows: [
                                                    Shadow(
                                                      offset: Offset(1, 1),
                                                      blurRadius: 3,
                                                      color: Colors.black
                                                          .withOpacity(0.5),
                                                    ),
                                                  ],
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '${giftCount}x',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                gift['name'],
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.9),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.auto_awesome,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      );

      // Replace original overlay with slide-out version
      overlayEntry.remove();
      Overlay.of(context).insert(slideOutOverlay);

      // Remove slide-out overlay after animation completes
      Future.delayed(slideOutDuration, () {
        slideOutOverlay.remove();
      });
    });
  }
}

// Enhanced Gift Bottom Sheet Widget
class GiftBottomSheet extends StatefulWidget {
  final String hostId;
  final String hostName;
  final String userId;
  final String userName;
  final String liveId;
  final int userCoins;
  final String? userProfileUrl;
  final Function(int) onCoinsUpdated;

  const GiftBottomSheet({
    Key? key,
    required this.hostId,
    required this.hostName,
    required this.userId,
    required this.userName,
    required this.liveId,
    required this.userCoins,
    this.userProfileUrl,
    required this.onCoinsUpdated,
  }) : super(key: key);

  @override
  State<GiftBottomSheet> createState() => _GiftBottomSheetState();
}

class _GiftBottomSheetState extends State<GiftBottomSheet>
    with TickerProviderStateMixin {
  final GiftService _giftService = GiftService();
  int _selectedGiftId = 1;
  int _giftCount = 1;
  bool _isSending = false;
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
    );

    _slideController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // Split gifts into pages (6 per page for better layout)
  List<List<Map<String, dynamic>>> get giftPages {
    List<List<Map<String, dynamic>>> pages = [];
    List<Map<String, dynamic>> currentPage = [];
    for (var gift in _giftService.giftTypes) {
      currentPage.add(gift);
      if (currentPage.length == 6) {
        pages.add(currentPage);
        currentPage = [];
      }
    }
    if (currentPage.isNotEmpty) {
      pages.add(currentPage);
    }
    return pages;
  }

  Widget _buildGradientBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1A3E), Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Handle bar
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.pink.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.favorite, color: Colors.pink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Send Gift',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      'to ${widget.hostName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoinsBalance() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withOpacity(0.15),
            Colors.orange.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Colors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Colors.amber,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.userCoins}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const Text(
                      ' coins',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.amber, Colors.orange],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder:
                      (context) => RechargeBottomSheet(
                        userId: widget.userId,
                        currentCoins: widget.userCoins,
                        onCoinsUpdated: widget.onCoinsUpdated,
                      ),
                );
              },
              child: const Text(
                'Top Up',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftGrid() {
    return Container(
      height: 280,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: PageView.builder(
        controller: _pageController,
        itemCount: giftPages.length,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
        },
        itemBuilder: (context, pageIndex) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: giftPages[pageIndex].length,
            itemBuilder: (context, index) {
              final gift = giftPages[pageIndex][index];
              final isSelected = _selectedGiftId == gift['id'];

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedGiftId = gift['id'];
                    });
                    HapticFeedback.lightImpact();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      gradient:
                          isSelected
                              ? LinearGradient(
                                colors: [
                                  Colors.purple.withOpacity(0.3),
                                  Colors.pink.withOpacity(0.3),
                                ],
                              )
                              : LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.05),
                                  Colors.white.withOpacity(0.02),
                                ],
                              ),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          isSelected
                              ? Border.all(color: Colors.purple, width: 2)
                              : Border.all(
                                color: Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: isSelected ? 1.1 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Lottie.network(
                            gift['animationAsset'],
                            width: 40,
                            height: 40,
                            fit: BoxFit.contain,
                            repeat: true,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.card_giftcard,
                                  color: Colors.white54,
                                  size: 24,
                                ),
                              );
                            },
                            // Add loading builder for better UX
                            frameBuilder: (context, child, composition) {
                              if (composition == null) {
                                return Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white54,
                                    ),
                                  ),
                                );
                              }
                              return child;
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          gift['name'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.monetization_on,
                                color: Colors.amber,
                                size: 10,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${gift['cost']}',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPageIndicators() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(giftPages.length, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _currentPage == index ? 20 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color:
                  _currentPage == index
                      ? Colors.purple
                      : Colors.white.withOpacity(0.3),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildQuantitySelector() {
    final selectedGift = _giftService.getGiftById(_selectedGiftId);
    final totalCost = selectedGift['cost'] * _giftCount;
    final canAfford = widget.userCoins >= totalCost;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Quantity',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.monetization_on,
                    color: Colors.amber,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$totalCost',
                    style: TextStyle(
                      color: canAfford ? Colors.amber : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Text(
                    ' total',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.remove, color: Colors.white),
                  onPressed:
                      _giftCount > 1
                          ? () {
                            setState(() {
                              _giftCount--;
                            });
                            HapticFeedback.lightImpact();
                          }
                          : null,
                ),
              ),
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.purple.withOpacity(0.3),
                      Colors.pink.withOpacity(0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.purple.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  'x$_giftCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _giftCount++;
                    });
                    HapticFeedback.lightImpact();
                  },
                ),
              ),
            ],
          ),
          if (!canAfford) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Need ${totalCost - widget.userCoins} more coins',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    final selectedGift = _giftService.getGiftById(_selectedGiftId);
    final totalCost = selectedGift['cost'] * _giftCount;
    final canAfford = widget.userCoins >= totalCost;

    return Container(
      margin: const EdgeInsets.all(20),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: canAfford && !_isSending ? _pulseAnimation.value : 1.0,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient:
                    canAfford
                        ? const LinearGradient(
                          colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
                        )
                        : LinearGradient(
                          colors: [
                            Colors.grey.withOpacity(0.3),
                            Colors.grey.withOpacity(0.2),
                          ],
                        ),
                borderRadius: BorderRadius.circular(16),
                boxShadow:
                    canAfford
                        ? [
                          BoxShadow(
                            color: Colors.purple.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                        : null,
              ),
              child: ElevatedButton(
                onPressed: (!canAfford || _isSending) ? null : _sendGift,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child:
                    _isSending
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.favorite,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              canAfford ? 'Send Gift' : 'Insufficient Balance',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendGift() async {
    final selectedGift = _giftService.getGiftById(_selectedGiftId);
    final totalCost = selectedGift['cost'] * _giftCount;

    if (widget.userCoins < totalCost) {
      _showInsufficientBalanceDialog(totalCost);
      return;
    }

    setState(() {
      _isSending = true;
    });

    final result = await _giftService.sendGift(
      liveId: widget.liveId,
      hostId: widget.hostId,
      userId: widget.userId,
      userName: widget.userName,
      giftId: _selectedGiftId,
      giftCount: _giftCount,
      senderProfileUrl: widget.userProfileUrl,
    );

    setState(() {
      _isSending = false;
    });

    if (result['success']) {
      widget.onCoinsUpdated(result['coins']);
      Navigator.pop(context);
      _showSuccessMessage(selectedGift['name']);
    } else {
      _showErrorMessage(result['message']);
    }
  }

  void _showInsufficientBalanceDialog(int totalCost) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF2A1A3E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Insufficient Balance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You need $totalCost coins but only have ${widget.userCoins} coins.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        color: Colors.amber,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Top up ${totalCost - widget.userCoins} more coins to send this gift',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.amber, Colors.orange],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder:
                          (context) => RechargeBottomSheet(
                            userId: widget.userId,
                            currentCoins: widget.userCoins,
                            onCoinsUpdated: widget.onCoinsUpdated,
                          ),
                    );
                  },
                  child: const Text(
                    'Top Up',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showSuccessMessage(String giftName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$giftName sent successfully! 💖',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Padding(
        // make room for keyboard or system insets
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            /* … */
          ),
          child: Stack(
            children: [
              _buildGradientBackground(),
              // wrap in scrollable
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    _buildCoinsBalance(),
                    const SizedBox(height: 8),
                    _buildGiftGrid(),
                    _buildPageIndicators(),
                    _buildQuantitySelector(),
                    _buildSendButton(),
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

// Recharge Bottom Sheet Widget (unchanged)
class RechargeBottomSheet extends StatefulWidget {
  final String userId;
  final int currentCoins;
  final Function(int) onCoinsUpdated;

  const RechargeBottomSheet({
    super.key,
    required this.userId,
    required this.currentCoins,
    required this.onCoinsUpdated,
  });

  @override
  State<RechargeBottomSheet> createState() => _RechargeBottomSheetState();
}

class _RechargeBottomSheetState extends State<RechargeBottomSheet> {
  final GiftService _giftService = GiftService();
  int _selectedAmount = 100;
  bool _isLoading = false;

  final List<int> _rechargeOptions = [100, 500, 1000, 2000, 5000, 10000];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recharge Coins',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.amber),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Balance',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.currentCoins}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.0,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _rechargeOptions.length,
            itemBuilder: (context, index) {
              final amount = _rechargeOptions[index];
              final isSelected = _selectedAmount == amount;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedAmount = amount;
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? Colors.amber.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        isSelected
                            ? Border.all(color: Colors.amber, width: 2)
                            : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: Colors.amber,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$amount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _isLoading
                      ? null
                      : () async {
                        setState(() {
                          _isLoading = true;
                        });

                        final result = await _giftService.rechargeCoins(
                          userId: widget.userId,
                          amount: _selectedAmount,
                        );

                        setState(() {
                          _isLoading = false;
                        });

                        if (result['success']) {
                          widget.onCoinsUpdated(result['coins']);
                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Successfully recharged $_selectedAmount coins!',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result['message']),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child:
                  _isLoading
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : const Text(
                        'Recharge Now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Note: This is a demo without real payment processing',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
