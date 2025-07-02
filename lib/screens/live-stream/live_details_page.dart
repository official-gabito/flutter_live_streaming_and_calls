// Gabito/Template developer: Gabriel Naandum
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_live_streaming_and_calls/service/gift_service.dart';
import 'package:flutter_live_streaming_and_calls/service/zego_config.dart';
import 'dart:math';
import 'package:zego_uikit_prebuilt_live_streaming/zego_uikit_prebuilt_live_streaming.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class LiveDetailsPage extends StatefulWidget {
  final String liveID;
  final String hostUserID;
  final String currentUserID;
  final bool isHost;
  final String? streamTitle;
  final bool isInSwiper;

  const LiveDetailsPage({
    super.key,
    required this.liveID,
    required this.hostUserID,
    required this.currentUserID,
    this.isHost = false,
    this.streamTitle,
    this.isInSwiper = false,
  });

  @override
  State<LiveDetailsPage> createState() => _LiveDetailsPageState();
}

class _LiveDetailsPageState extends State<LiveDetailsPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GiftService _giftService = GiftService();
  bool _likeLoading = true; // Fixed initialization (was incorrectly constant)
  bool _isInitialGiftLoad = true; // Flag for initial snapshot
  late String likedUserId;
  StreamSubscription<QuerySnapshot>?
  _giftsSubscription; // Store the subscription
  String _userName = '';
  String _userProfileUrl = '';
  String _hostName = '';
  bool _dataLoaded = false;
  final Color _themeColor = const Color(0xFFA84BC2);
  bool _isStreamActive = true;
  bool _isStreamStarted = false;

  Map<String, int> _userEngagement = {};
  List<Map<String, dynamic>> _topGifters = [];
  Timer? _engagementTimer;

  int _likeCount = 0;
  List<LikeAnimation> _likeAnimations = [];
  bool _isLiking = false;
  int _userCoins = 0;
  DateTime? _startTime;
  bool _hasLiked = false;

  late AnimationController _animationController;

  bool _timerActive = false;
  Timer? _streamTimer;

  String _token = '';

  final TextEditingController _commentController = TextEditingController();
  final ScrollController _commentScrollController = ScrollController();

  Timer? _heartbeatTimer;
  StreamSubscription<DocumentSnapshot>? _streamStatusSubscription;
  bool _isTerminating = false;
  static const _heartbeatInterval = Duration(seconds: 10);
  static const _heartbeatTimeout = Duration(seconds: 40);

  String _streamTitle = '';

  @override
  void initState() {
    super.initState();
    likedUserId = widget.hostUserID; // Initialize likedUserId

    _userProfileUrl = '';
    _hostName = '';
    _topGifters = [];
    _dataLoaded = false;
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _token = ZegoConfig.generateToken(
      widget.currentUserID,
      role: widget.isHost ? 1 : 2,
      forceSigned: true,
    );

    final signalingPlugin = ZegoUIKitSignalingPlugin();
    ZegoUIKit.instance.installPlugins([signalingPlugin]);

    _initConnection().then((_) {
      _fetchUserData().then((_) {
        setState(() {
          _dataLoaded = true;
        });

        if (!widget.isHost) {
          _addViewerToStream();
        }

        _getLiveStreamData();
        _getUserCoins();
        _startStreamTimer();
        _fetchTopGifters();

        _firestore
            .collection('live_streams')
            .doc(widget.liveID)
            .collection('gifts')
            .snapshots()
            .listen((_) {
              _fetchTopGifters();
            });
        _firestore
            .collection('live_streams')
            .doc(widget.liveID)
            .collection('viewers')
            .snapshots()
            .listen((_) {
              _fetchTopGifters();
            });

        if (widget.isHost) {
          _streamTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
            if (!mounted || !_isStreamActive) {
              timer.cancel();
              return;
            }
            _firestore
                .collection('live_streams')
                .doc(widget.liveID)
                .update({'lastUpdated': FieldValue.serverTimestamp()})
                .catchError((e) {
                  debugPrint('Error updating lastUpdated: $e');
                });
          });
        }
      });
    });

    _streamStatusSubscription = _firestore
        .collection('live_streams')
        .doc(widget.liveID)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          if (!snapshot.exists || snapshot.data()?['status'] == 'ended') {
            _handleStreamTermination(
              widget.isHost ? 'You have ended the stream' : 'Stream has ended',
            );
          }
        });

    _startEngagementTracking();
    if (widget.isHost) {
      _startHostHeartbeat();
    } else {
      _startHeartbeatCheck();
    }
    _initConnection().then((_) {
      _fetchUserData().then((_) {
        setState(() {
          _dataLoaded = true;
        });
      });
    });
  }

  void _startEngagementTracking() {
    _engagementTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted || !_isStreamActive) {
        timer.cancel();
        return;
      }
      _updateEngagementScores();
    });
  }

  void _updateEngagementScores() {
    _firestore
        .collection('live_streams')
        .doc(widget.liveID)
        .collection('viewers')
        .get()
        .then((viewers) {
          for (var viewer in viewers.docs) {
            final userId = viewer.data()['userId'] as String;
            final joinedAt = viewer.data()['joinedAt'] as Timestamp;
            final duration =
                DateTime.now().difference(joinedAt.toDate()).inMinutes;

            if (_userEngagement.containsKey(userId)) {
              _userEngagement[userId] = _userEngagement[userId]! + 1;
            } else {
              _userEngagement[userId] = duration;
            }
          }
        });
  }

  Future<void> _initConnection() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _startStreamTimer() {
    _firestore.collection('live_streams').doc(widget.liveID).get().then((doc) {
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['startedAt'] != null) {
          setState(() {
            _startTime = (data['startedAt'] as Timestamp).toDate();
            _timerActive = true;
          });
          Future.delayed(const Duration(seconds: 1), _updateStreamDuration);
        }
      }
    });
  }

  void _updateStreamDuration() {
    if (!mounted || !_timerActive || _startTime == null) return;
    setState(() {});
    Future.delayed(const Duration(seconds: 1), _updateStreamDuration);
  }

  Future<void> _fetchUserData() async {
    try {
      final currentUserDoc =
          await _firestore.collection('users').doc(widget.currentUserID).get();
      if (currentUserDoc.exists) {
        final userData = currentUserDoc.data()!;
        String firstName = userData['firstName'] ?? '';
        String lastName = userData['lastName'] ?? '';
        if (firstName.isNotEmpty || lastName.isNotEmpty) {
          _userName = '$firstName $lastName'.trim();
        } else {
          _userName = userData['username'] ?? '';
        }
        if (_userName.isEmpty) {
          _userName =
              "User_${widget.currentUserID.substring(0, min(6, widget.currentUserID.length))}";
        }
        if (userData['photos'] != null &&
            (userData['photos'] as List).isNotEmpty) {
          _userProfileUrl = userData['photos'][0];
        }
      }

      final hostDoc =
          await _firestore.collection('users').doc(widget.hostUserID).get();
      if (hostDoc.exists) {
        final hostData = hostDoc.data()!;
        String firstName = hostData['firstName'] ?? '';
        String lastName = hostData['lastName'] ?? '';
        if (firstName.isNotEmpty || lastName.isNotEmpty) {
          _hostName = '$firstName $lastName'.trim();
        } else {
          _hostName = hostData['username'] ?? '';
        }
        if (_hostName.isEmpty) {
          _hostName =
              "Host_${widget.hostUserID.substring(0, min(6, widget.hostUserID.length))}";
        }
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
  }

  Future<void> _getUserCoins() async {
    final userWalletDoc =
        await _firestore.collection('wallets').doc(widget.currentUserID).get();
    if (userWalletDoc.exists) {
      setState(() {
        _userCoins = userWalletDoc.data()?['coins'] ?? 0;
      });
    }
    _firestore
        .collection('wallets')
        .doc(widget.currentUserID)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {
            setState(() {
              _userCoins = snapshot.data()?['coins'] ?? 0;
            });
          }
        });
  }

  Future<void> _getLiveStreamData() async {
    try {
      final streamDoc =
          await _firestore.collection('live_streams').doc(widget.liveID).get();
      if (streamDoc.exists) {
        setState(() {
          _likeCount = streamDoc.data()?['likeCount'] ?? 0;
          _streamTitle = streamDoc.data()?['title'] ?? '';
        });
      }
      _firestore
          .collection('live_streams')
          .doc(widget.liveID)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists && mounted) {
              setState(() {
                _likeCount = snapshot.data()?['likeCount'] ?? 0;
                _streamTitle = snapshot.data()?['title'] ?? '';
              });
            }
          });

      // Gifts listener with initial load check
      _giftsSubscription = _firestore
          .collection('live_streams')
          .doc(widget.liveID)
          .collection('gifts')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snapshot) {
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final giftData = change.doc.data();
                if (giftData != null && mounted) {
                  if (!_isInitialGiftLoad) {
                    // Only show animations after initial load
                    _giftService.showGiftAnimation(
                      context: context,
                      giftData: giftData,
                    );
                  }
                }
              }
            }
            _isInitialGiftLoad = false; // Mark initial load as complete
          });
    } catch (e) {
      debugPrint('Error getting live stream data: $e');
    }
  }

  Future<void> _fetchTopGifters() async {
    try {
      final giftsSnapshot =
          await _firestore
              .collection('live_streams')
              .doc(widget.liveID)
              .collection('gifts')
              .get();

      Map<String, double> giftTotals = {};
      for (var doc in giftsSnapshot.docs) {
        final data = doc.data();
        if (data.containsKey('senderId') && data.containsKey('totalCost')) {
          final userId = data['senderId'] as String;
          final totalCost = (data['totalCost'] as num).toDouble();
          giftTotals[userId] = (giftTotals[userId] ?? 0) + totalCost;
        }
      }

      List<MapEntry<String, double>> sortedGifters =
          giftTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

      final viewersSnapshot =
          await _firestore
              .collection('live_streams')
              .doc(widget.liveID)
              .collection('viewers')
              .orderBy('joinedAt', descending: true)
              .get();

      final activeViewers =
          viewersSnapshot.docs.map((doc) {
              final data = doc.data();
              final joinedAt = (data['joinedAt'] as Timestamp).toDate();
              final duration = DateTime.now().difference(joinedAt).inMinutes;
              return MapEntry(doc.id, duration);
            }).toList()
            ..sort((a, b) => b.value.compareTo(a.value));

      final List<Map<String, dynamic>> topProfiles = [];
      Set<String> addedUsers = {};

      for (var gifter in sortedGifters) {
        if (topProfiles.length >= 3) break;
        if (addedUsers.contains(gifter.key)) continue;

        final userData =
            await _firestore.collection('users').doc(gifter.key).get();
        if (userData.exists) {
          final data = userData.data()!;
          topProfiles.add({
            'userId': gifter.key,
            'profileUrl': data['photos']?[0] ?? '',
            'amount': gifter.value,
            'isGifter': true,
          });
          addedUsers.add(gifter.key);
        }
      }

      for (var viewer in activeViewers) {
        if (topProfiles.length >= 3) break;
        if (addedUsers.contains(viewer.key)) continue;

        final userData =
            await _firestore.collection('users').doc(viewer.key).get();
        if (userData.exists) {
          final data = userData.data()!;
          topProfiles.add({
            'userId': viewer.key,
            'profileUrl': data['photos']?[0] ?? '',
            'duration': viewer.value,
            'isGifter': false,
          });
          addedUsers.add(viewer.key);
        }
      }

      if (mounted) {
        setState(() {
          _topGifters = topProfiles;
        });
      }
    } catch (e) {
      debugPrint('Error fetching top profiles: $e');
    }
  }

  Widget _buildTopUsersRow() {
    return Container(
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            _topGifters.asMap().entries.map((entry) {
              final index = entry.key;
              final user = entry.value;
              final isGifter = user['isGifter'] == true;
              return Container(
                key: ValueKey(user['userId']), // Add unique key
                margin: EdgeInsets.only(
                  right: index < _topGifters.length - 1 ? 4 : 0,
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isGifter ? Colors.amber : Colors.blue,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child:
                            user['profileUrl'].toString().isNotEmpty
                                ? CachedNetworkImage(
                                  imageUrl: user['profileUrl'],
                                  width: 25,
                                  height: 25,
                                  fit: BoxFit.cover,
                                  placeholder:
                                      (context, url) => _buildPlaceholder(),
                                  errorWidget:
                                      (context, url, error) =>
                                          _buildPlaceholder(),
                                )
                                : _buildPlaceholder(),
                      ),
                    ),
                    if (isGifter)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 15,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                            horizontal: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(25),
                              bottomRight: Radius.circular(25),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              NumberFormat.compact().format(user['amount']),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 30,
      height: 30,
      color: Colors.grey[800],
      child: const Icon(Icons.person, size: 20, color: Colors.white),
    );
  }

  Widget _buildLikeCount() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite, color: Colors.red, size: 20),
          const SizedBox(width: 4),
          Text(
            NumberFormat.compact().format(_likeCount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _startHostHeartbeat() {
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (!mounted || !_isStreamActive) {
        timer.cancel();
        return;
      }
      _firestore.collection('live_streams').doc(widget.liveID).update({
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  void _startHeartbeatCheck() {
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (!mounted || !_isStreamActive) {
        timer.cancel();
        return;
      }
      _checkHostActivity();
    });
  }

  int _missedHeartbeats = 0;
  static const int maxMissedHeartbeats = 3;

  Future<void> _checkHostActivity() async {
    try {
      final doc =
          await _firestore.collection('live_streams').doc(widget.liveID).get();
      if (!doc.exists) {
        _handleStreamTermination('Stream no longer exists');
        return;
      }
      final data = doc.data();
      if (data?['status'] == 'ended') {
        _handleStreamTermination('Stream has ended');
        return;
      }
      final lastUpdated = data?['lastUpdated'] as Timestamp?;
      if (lastUpdated != null && !widget.isHost) {
        final timeSinceUpdate = DateTime.now().difference(lastUpdated.toDate());
        if (timeSinceUpdate > _heartbeatTimeout) {
          _missedHeartbeats++;
          if (_missedHeartbeats >= maxMissedHeartbeats) {
            await _firestore
                .collection('live_streams')
                .doc(widget.liveID)
                .update({
                  'status': 'ended',
                  'endedAt': FieldValue.serverTimestamp(),
                });
            _handleStreamTermination('Host is unavailable');
          }
        } else {
          _missedHeartbeats = 0;
        }
      }
    } catch (e) {
      debugPrint('Error checking host activity: $e');
    }
  }

  void _onEndLiveStreaming() {
    if (_isTerminating) return;
    _handleStreamTermination('You have ended the stream');
  }

  void _handleStreamTermination(String message) {
    if (_isTerminating || !mounted) return;
    _isTerminating = true;

    if (widget.isHost) {
      _firestore
          .collection('live_streams')
          .doc(widget.liveID)
          .update({
            'status': 'ended',
            'endedAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
            'viewerCount': 0,
          })
          .then((_) => _cleanupViewers())
          .catchError((e) => debugPrint('Error ending stream: $e'));
      Navigator.pop(context);
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          // Auto-dismiss after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            }
          });

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.grey.shade900.withOpacity(0.95),
                    Colors.black.withOpacity(0.98),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: Colors.grey.shade700.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon with animation
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.videocam_off_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  const Text(
                    'Stream Ended',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Message
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Progress indicator
                  Column(
                    children: [
                      Text(
                        'Closing automatically...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Manual close button
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop(); // Close the dialog first
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          Navigator.of(
                            context,
                          ).pop(); // Then pop the live stream page
                        }
                      });
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                    child: const Text(
                      'Close Now',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _cleanupViewers() async {
    try {
      final viewers =
          await _firestore
              .collection('live_streams')
              .doc(widget.liveID)
              .collection('viewers')
              .get();

      for (var doc in viewers.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error cleaning up viewers: $e');
    }
  }

  @override
  void dispose() {
    _streamStatusSubscription?.cancel();
    _giftsSubscription?.cancel(); // Cancel gifts subscription
    _heartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _timerActive = false;
    _streamTimer?.cancel();
    _commentController.dispose();
    _commentScrollController.dispose();
    _engagementTimer?.cancel();
    if (!widget.isHost) {
      _removeViewerFromStream();
    }
    if (widget.isHost && _isStreamActive && !_isTerminating) {
      _onEndLiveStreaming();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.isHost && _isStreamActive) {
      if (state == AppLifecycleState.paused) {
        _firestore.collection('live_streams').doc(widget.liveID).update({
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else if (state == AppLifecycleState.detached) {
        _onEndLiveStreaming();
      }
    }
  }

  void _addViewerToStream() async {
    try {
      // Add viewer to the 'viewers' subcollection
      await _firestore
          .collection('live_streams')
          .doc(widget.liveID)
          .collection('viewers')
          .doc(widget.currentUserID)
          .set({
            'userId': widget.currentUserID,
            'username': _userName,
            'profileUrl': _userProfileUrl,
            'joinedAt': FieldValue.serverTimestamp(),
          });
      await _firestore.collection('live_streams').doc(widget.liveID).update({
        'viewerCount': FieldValue.increment(1),
      });

      // Add a join message to the 'comments' subcollection
      await _firestore
          .collection('live_streams')
          .doc(widget.liveID)
          .collection('comments')
          .add({
            'userId': widget.currentUserID,
            'userName': _userName,
            'profileUrl': _userProfileUrl,
            'message': 'joined the stream',
            'timestamp': FieldValue.serverTimestamp(),
            'isHost': false,
            'type': 'join', // Distinguish join messages from regular comments
          });
    } catch (e) {
      debugPrint('Error adding viewer: $e');
    }
  }

  void _removeViewerFromStream() async {
    try {
      await _firestore
          .collection('live_streams')
          .doc(widget.liveID)
          .collection('viewers')
          .doc(widget.currentUserID)
          .delete();
      await _firestore.collection('live_streams').doc(widget.liveID).update({
        'viewerCount': FieldValue.increment(-1),
      });
    } catch (e) {
      debugPrint('Error removing viewer: $e');
    }
  }

  void _showEndLiveStreamConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'End Live Stream?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Are you sure you want to end this live stream? This cannot be undone.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _onEndLiveStreaming();
                },
                child: const Text(
                  'End Stream',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _handleLike() async {
    if (!mounted) return;
    final random = Random();
    final burstCount = 3 + random.nextInt(3); // 3 to 5 hearts
    final startY = MediaQuery.of(context).size.height - 100;

    setState(() {
      for (int i = 0; i < burstCount; i++) {
        final startX = 20 + random.nextDouble() * 60;
        final endX = startX + (random.nextDouble() - 0.5) * 40;
        final endY = startY - 200 - random.nextDouble() * 100;
        final duration = Duration(milliseconds: 1000 + random.nextInt(1000));

        _likeAnimations.add(
          LikeAnimation(
            startPosition: Offset(startX, startY),
            endPosition: Offset(endX, endY),
            duration: duration,
          ),
        );

        // Schedule removal after animation duration
        Future.delayed(duration, () {
          if (mounted) {
            setState(() {
              _likeAnimations.removeWhere((anim) => anim.duration == duration);
            });
          }
        });
      }
    });

    try {
      await _firestore.collection('live_streams').doc(widget.liveID).update({
        'likeCount': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('Error updating like count: $e');
    }
  }

  void _handleTap() {
    if (!_isLiking) {
      setState(() {
        _isLiking = true;
      });
      _handleLike().then((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _isLiking = false;
            });
          }
        });
      });
    }
  }

  void _shareLiveStream() {
    final String shareText =
        'Join my live stream on Gabito! Stream ID:  24{widget.liveID}\n\n'
        'Host: $_hostName\n'
        'Title:  24{widget.streamTitle ?? "Live Stream"}\n\n'
        'Download Gabito app to watch: https://gabito.dev/download';
    Share.share(shareText);
  }

  void _showGiftDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => GiftBottomSheet(
            hostId: widget.hostUserID,
            hostName: _hostName,
            userId: widget.currentUserID,
            userName: _userName,
            liveId: widget.liveID,
            userCoins: _userCoins,
            userProfileUrl: _userProfileUrl,
            onCoinsUpdated: (newAmount) {
              setState(() {
                _userCoins = newAmount;
              });
            },
          ),
    );
  }

  void _sendComment() async {
    final trimmedComment = _commentController.text.trim();
    if (trimmedComment.isEmpty) return;
    if (widget.liveID.isEmpty || widget.currentUserID.isEmpty) {
      debugPrint(
        'Invalid liveID: "${widget.liveID}" or currentUserID: "${widget.currentUserID}"',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid live stream or user ID. Please try again.'),
          ),
        );
      }
      return;
    }
    try {
      final liveStreamDoc =
          await _firestore.collection('live_streams').doc(widget.liveID).get();
      if (!liveStreamDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This live stream no longer exists')),
          );
        }
        return;
      }
      final userDoc =
          await _firestore.collection('users').doc(widget.currentUserID).get();
      if (!userDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User profile not found')),
          );
        }
        return;
      }
      final userData = userDoc.data()!;
      String userName =
          userData['firstName'] != null
              ? "${userData['firstName']} ${userData['lastName']}"
              : userData['username'] ?? _userName;
      String profileUrl = '';
      if (userData['photos'] != null &&
          (userData['photos'] as List).isNotEmpty) {
        profileUrl = userData['photos'][0];
      }
      await _firestore
          .collection('live_streams')
          .doc(widget.liveID)
          .collection('comments')
          .add({
            'userId': widget.currentUserID,
            'userName': userName.trim(),
            'profileUrl': profileUrl,
            'message': trimmedComment,
            'timestamp': FieldValue.serverTimestamp(),
            'isHost': widget.isHost,
            'type': 'comment', // Add type field for regular comments
          });
      _commentController.clear();
    } catch (e) {
      debugPrint('Error sending comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final isHostComment = comment['isHost'] == true;
    final isJoinMessage = comment['type'] == 'join';

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.08),
                    Colors.white.withOpacity(0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enhanced Profile Picture
                  _buildProfilePicture(comment, isHostComment),
                  const SizedBox(width: 12),

                  // Content Section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isJoinMessage)
                          _buildJoinMessage(comment)
                        else
                          _buildRegularComment(comment, isHostComment),
                      ],
                    ),
                  ),

                  // Action Icons
                  if (!isJoinMessage) _buildActionIcons(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfilePicture(
    Map<String, dynamic> comment,
    bool isHostComment,
  ) {
    return Stack(
      children: [
        // Profile picture container with glow effect for host
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient:
                isHostComment
                    ? LinearGradient(
                      colors: [
                        const Color(0xFFA84BC2),
                        const Color(0xFF6B46C1),
                      ],
                    )
                    : null,
            boxShadow:
                isHostComment
                    ? [
                      BoxShadow(
                        color: const Color(0xFFA84BC2).withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                    : null,
          ),
          padding: EdgeInsets.all(isHostComment ? 2 : 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child:
                comment['profileUrl']?.toString().isNotEmpty == true
                    ? CachedNetworkImage(
                      imageUrl: comment['profileUrl'],
                      width: 30,
                      height: 30,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.grey[700]!, Colors.grey[800]!],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 24,
                              color: Colors.white54,
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.grey[700]!, Colors.grey[800]!],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 24,
                              color: Colors.white54,
                            ),
                          ),
                    )
                    : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.grey[700]!, Colors.grey[800]!],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 24,
                        color: Colors.white54,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  Widget _buildJoinMessage(Map<String, dynamic> comment) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withOpacity(0.2),
            Colors.purple.withOpacity(0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.waving_hand, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${comment['userName']} joined the stream',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontStyle: FontStyle.italic,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(
                    offset: const Offset(0, 1),
                    blurRadius: 2.0,
                    color: Colors.black.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegularComment(
    Map<String, dynamic> comment,
    bool isHostComment,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Username and badges row
        Row(
          children: [
            Flexible(
              child: Text(
                comment['userName'] ?? 'Unknown User',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 15,
                  shadows: [
                    Shadow(
                      offset: const Offset(0, 1),
                      blurRadius: 2.0,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ],
                ),
              ),
            ),
            if (isHostComment) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFFA84BC2), const Color(0xFF6B46C1)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    const Text(
                      'Host',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Verified badge example
            if (comment['isVerified'] == true) ...[
              const SizedBox(width: 6),
              Icon(Icons.verified, size: 16, color: Colors.blue),
            ],
          ],
        ),

        const SizedBox(height: 1),

        // Message content
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.6),
              width: 0.5,
            ),
          ),
          child: Text(
            comment['message'] ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 15,
              height: 1.3,
              shadows: [
                Shadow(
                  offset: const Offset(0, 1),
                  blurRadius: 2.0,
                  color: Colors.black.withOpacity(0.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionIcons() {
    return Column(
      children: [
        _buildActionButton(
          icon:
              _likeLoading
                  ? Icons.favorite_border
                  : (_hasLiked ? Icons.favorite : Icons.favorite_border),
          iconColor: _hasLiked ? Colors.red : Colors.grey,
          onTap: _handleTap,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.grey,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
        ),
        child: Icon(icon, size: 16, color: iconColor), // Use iconColor
      ),
    );
  }

  Widget _buildCommentSection() {
    if (widget.isHost) {
      return Stack(
        children: [
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.4, // Reduced height
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                  stops: const [0.0, 0.2],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    _firestore
                        .collection('live_streams')
                        .doc(widget.liveID)
                        .collection('comments')
                        .orderBy('timestamp', descending: true)
                        .limit(50)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const SizedBox();
                  }
                  if (!snapshot.hasData) {
                    return const SizedBox();
                  }
                  final comments = snapshot.data!.docs;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_commentScrollController.hasClients) {
                      _commentScrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  });
                  return ListView.builder(
                    controller: _commentScrollController,
                    reverse: true,
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment =
                          comments[index].data() as Map<String, dynamic>;
                      return _buildCommentItem(comment);
                    },
                  );
                },
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 16,
            child: Container(
              height: 40,
              width: MediaQuery.of(context).size.width * 0.3,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(
                      CupertinoIcons.conversation_bubble,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showHostCommentDialog(),
                      child: Container(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Type...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: MediaQuery.of(context).size.height * 0.4, // Reduced height
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            Expanded(
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                    stops: const [0.0, 0.2],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      _firestore
                          .collection('live_streams')
                          .doc(widget.liveID)
                          .collection('comments')
                          .orderBy('timestamp', descending: true)
                          .limit(50)
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const SizedBox();
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox();
                    }
                    final comments = snapshot.data!.docs;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_commentScrollController.hasClients) {
                        _commentScrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                    return ListView.builder(
                      controller: _commentScrollController,
                      reverse: true,
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final comment =
                            comments[index].data() as Map<String, dynamic>;
                        return _buildCommentItem(comment);
                      },
                    );
                  },
                ),
              ),
            ),
            // Enhanced input section
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.grey.shade700.withOpacity(0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Enhanced input field
                    Expanded(
                      child: Container(
                        height: 45,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.grey.shade600.withOpacity(0.3),
                            width: 0.5,
                          ),
                        ),
                        child: TextField(
                          controller: _commentController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _sendComment(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Enhanced send button
                    Container(
                      height: 45,
                      width: 45,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_themeColor.withOpacity(0.8), _themeColor],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _themeColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        onPressed: _sendComment,
                      ),
                    ),
                    if (!widget.isHost) ...[
                      const SizedBox(width: 8),
                      // Enhanced gift button
                      Container(
                        height: 45,
                        width: 45,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.purple.shade400,
                              Colors.purple.shade600,
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(
                            CupertinoIcons.gift_fill,
                            size: 20,
                            color: Colors.white,
                          ),
                          onPressed: _showGiftDialog,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Enhanced share button
                      Container(
                        height: 45,
                        width: 45,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade400,
                              Colors.blue.shade600,
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(
                            CupertinoIcons.arrowshape_turn_up_right,
                            size: 20,
                            color: Colors.white,
                          ),
                          onPressed: _shareLiveStream,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHostCommentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16.0),
                topRight: Radius.circular(16.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8.0,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _commentController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.0),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      suffixIcon: IconButton(
                        icon: Icon(Icons.send),
                        color: _themeColor,
                        onPressed: () {
                          _sendComment();
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (text) {
                      _sendComment();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final topSafeArea = MediaQuery.of(context).padding.top;

    if (!_dataLoaded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black,
                Colors.black.withOpacity(0.8),
                Colors.purple.shade400.withOpacity(0.1),
                Colors.black,
              ],
              stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.2),
                duration: const Duration(milliseconds: 1000),
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.pink.shade400, Colors.red.shade400],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pink.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 35,
                      ),
                    ),
                  );
                },
                onEnd: () {
                  setState(() {});
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.3, end: 1.0),
                    duration: Duration(milliseconds: 600 + (index * 200)),
                    builder: (context, opacity, child) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(opacity),
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                    onEnd: () {
                      setState(() {});
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              Text(
                'Connecting to Live Stream...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Finding your perfect match',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return WillPopScope(
      onWillPop: () async {
        if (widget.isHost) {
          _showEndLiveStreamConfirmation();
          return false;
        }
        if (widget.isInSwiper) {
          Navigator.pop(context); // Let the swiper handle navigation
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            SafeArea(
              child: ZegoUIKitPrebuiltLiveStreaming(
                appID: ZegoConfig.appID,
                appSign: ZegoConfig.appSign,
                userID: widget.currentUserID,
                userName:
                    _userName.isNotEmpty ? _userName : widget.currentUserID,
                liveID: widget.liveID,
                config: _getLiveStreamConfig(),
                token: _token,
                events: ZegoUIKitPrebuiltLiveStreamingEvents(
                  onLeaveConfirmation: (context, defaultAction) async {
                    if (widget.isHost) {
                      _showEndLiveStreamConfirmation();
                      return false;
                    }
                    return true;
                  },
                  onStateUpdated: (state) {
                    if (state == ZegoLiveStreamingState.living) {
                      setState(() {
                        _isStreamStarted = true;
                      });
                      if (widget.isHost) {
                        _firestore
                            .collection('live_streams')
                            .doc(widget.liveID)
                            .update({
                              'lastUpdated': FieldValue.serverTimestamp(),
                              'status': 'live',
                            });
                      }
                    } else if (state == ZegoLiveStreamingState.ended) {
                      _handleStreamTermination('Stream has ended');
                    }
                  },
                  onError: (error) {
                    debugPrint('Zego error: ${error.code} - ${error.message}');
                    if (error.code == 103010) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Room is full, please try again later'),
                        ),
                      );
                    } else {}
                  },
                  onEnded: (
                    ZegoLiveStreamingEndEvent event,
                    VoidCallback defaultAction,
                  ) {
                    if (mounted) {
                      Navigator.pop(
                        context,
                        widget.isHost ? 'stream_ended' : null,
                      );
                    }
                    defaultAction();
                  },
                  user: ZegoLiveStreamingUserEvents(
                    onEnter: (user) {
                      debugPrint('User entered: ${user.id}');
                    },
                    onLeave: (user) {
                      debugPrint('User left: ${user.id}');
                    },
                  ),
                  inRoomMessage: ZegoLiveStreamingInRoomMessageEvents(
                    onLocalSend: (message) {
                      debugPrint('Message sent: ${message.message}');
                    },
                  ),
                ),
              ),
            ),
            if ((widget.isHost && _isStreamStarted) || !widget.isHost) ...[
              // Stream title widget - responsive positioning
              Positioned(
                top: topSafeArea + (screenHeight * 0.10),
                left: screenWidth * 0.04,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.antenna_radiowaves_left_right,
                        color: Colors.orange,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _streamTitle.isNotEmpty
                            ? _streamTitle
                            : widget.streamTitle ?? 'Popular LIVE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Top gifters - responsive positioning
              Positioned(
                top: topSafeArea + (screenHeight * 0.06),
                right: screenWidth * 0.33,
                child:
                    _topGifters.isNotEmpty
                        ? _buildTopUsersRow()
                        : const SizedBox(),
              ),
              // Like count - responsive positioning
              Positioned(
                top: topSafeArea + (screenHeight * 0.12),
                left: screenWidth * 0.03,
                child: _buildLikeCount(),
              ),
              if (_likeAnimations.isNotEmpty)
                Stack(
                  children:
                      _likeAnimations.map((animation) {
                        return AnimatedLikeIcon(
                          startPosition: animation.startPosition,
                          endPosition: animation.endPosition,
                          duration: animation.duration,
                        );
                      }).toList(),
                ),
              if (!widget.isHost)
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTap: _handleTap,
                    behavior: HitTestBehavior.translucent,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              _buildCommentSection(),
            ],
            if (!widget.isHost)
              Positioned(
                top: MediaQuery.of(context).padding.top + 45,
                right: 25,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    color: Colors.transparent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ZegoUIKitPrebuiltLiveStreamingConfig _getLiveStreamConfig() {
    if (widget.isHost) {
      return ZegoUIKitPrebuiltLiveStreamingConfig.host()
        ..turnOnCameraWhenJoining = true
        ..turnOnMicrophoneWhenJoining = true
        ..useSpeakerWhenJoining = true
        ..avatarBuilder = (
          BuildContext context,
          Size size,
          ZegoUIKitUser? user,
          Map extraInfo,
        ) {
          return _buildUserAvatar(user?.id ?? '');
        }
        ..audioVideoViewConfig = ZegoPrebuiltAudioVideoViewConfig(
          showAvatarInAudioMode: true,
          showSoundWavesInAudioMode: true,
          useVideoViewAspectFill: true,
        )
        ..plugins = [ZegoUIKitSignalingPlugin()]
        ..topMenuBarConfig = ZegoTopMenuBarConfig(
          buttons: [
            ZegoMenuBarButtonName.toggleCameraButton,
            ZegoMenuBarButtonName.toggleMicrophoneButton,
            ZegoMenuBarButtonName.switchCameraButton,
          ],
        )
        ..bottomMenuBarConfig = ZegoBottomMenuBarConfig(
          showInRoomMessageButton: false,
        )
        ..inRoomMessageConfig = ZegoInRoomMessageConfig(visible: false)
        ..markAsLargeRoom = true;
    }
    return ZegoUIKitPrebuiltLiveStreamingConfig.audience()
      ..layout = ZegoLayout.pictureInPicture()
      ..turnOnCameraWhenJoining = false
      ..turnOnMicrophoneWhenJoining = false
      ..useSpeakerWhenJoining = true
      ..avatarBuilder = (
        BuildContext context,
        Size size,
        ZegoUIKitUser? user,
        Map extraInfo,
      ) {
        return _buildUserAvatar(user?.id ?? '');
      }
      ..plugins = [ZegoUIKitSignalingPlugin()]
      ..audioVideoViewConfig = ZegoPrebuiltAudioVideoViewConfig(
        showAvatarInAudioMode: true,
        showSoundWavesInAudioMode: true,
        useVideoViewAspectFill: true,
      )
      ..bottomMenuBarConfig = ZegoBottomMenuBarConfig(
        audienceButtons: [],
        showInRoomMessageButton: false,
      )
      ..inRoomMessageConfig = ZegoInRoomMessageConfig(visible: false)
      ..markAsLargeRoom = true;
  }

  Widget _buildUserAvatar(String userId) {
    if (userId == widget.hostUserID) {
      return FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('users').doc(widget.hostUserID).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return _buildPlaceholderAvatar();
          }
          final hostData = snapshot.data!.data() as Map<String, dynamic>?;
          final hostPhotoUrl =
              hostData?['photos']?.isNotEmpty == true
                  ? hostData!['photos'][0] as String
                  : '';
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _themeColor, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: CachedNetworkImage(
                imageUrl: hostPhotoUrl,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildPlaceholderAvatar(),
                errorWidget: (context, url, error) => _buildPlaceholderAvatar(),
              ),
            ),
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(userId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final photoUrl =
              userData?['photos']?.isNotEmpty == true
                  ? userData!['photos'][0] as String
                  : null;

          if (photoUrl != null) {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      userId == widget.hostUserID ? _themeColor : Colors.white,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: CachedNetworkImage(
                  imageUrl: photoUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _buildPlaceholderAvatar(),
                  errorWidget:
                      (context, url, error) => _buildPlaceholderAvatar(),
                ),
              ),
            );
          }
        }
        return _buildPlaceholderAvatar();
      },
    );
  }

  Widget _buildPlaceholderAvatar() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey[600]!, width: 1),
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 24),
    );
  }
}

class LikeAnimation {
  final Offset startPosition;
  final Offset endPosition;
  final Duration duration;
  final double delay;

  LikeAnimation({
    required this.startPosition,
    required this.endPosition,
    required this.duration,
    this.delay = 0.0,
  });
}

class AnimatedLikeIcon extends StatefulWidget {
  final Offset startPosition;
  final Offset endPosition;
  final Duration duration;
  final double delay;

  const AnimatedLikeIcon({
    super.key,
    required this.startPosition,
    required this.endPosition,
    required this.duration,
    this.delay = 0.0,
  });

  @override
  State<AnimatedLikeIcon> createState() => _AnimatedLikeIconState();
}

class _AnimatedLikeIconState extends State<AnimatedLikeIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    // Position animation with more natural curve
    _positionAnimation = Tween<Offset>(
      begin: widget.startPosition,
      end: widget.endPosition,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Opacity fades out in the last 30% of animation
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 1.0, curve: Curves.easeInQuad),
      ),
    );

    // Scale starts small, grows quickly, then shrinks as it fades
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.3,
          end: 1.4,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
      TweenSequenceItem(tween: Tween<double>(begin: 1.4, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.8), weight: 30),
    ]).animate(_controller);

    // Subtle rotation for more dynamic feel
    _rotationAnimation = Tween<double>(
      begin: -0.1,
      end: 0.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Start animation with delay
    if (widget.delay > 0) {
      Future.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _positionAnimation.value.dx,
          top: _positionAnimation.value.dy,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Transform.rotate(
                angle: _rotationAnimation.value,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.red,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Helper class to manage multiple like animations (TikTok-style burst)
class LikeAnimationManager {
  static List<LikeAnimation> createBurstAnimation(Offset tapPosition) {
    final List<LikeAnimation> animations = [];
    final random = Random();

    // Create 5-8 hearts with random positions and delays
    final heartCount = 5 + random.nextInt(4);

    for (int i = 0; i < heartCount; i++) {
      final angle = (i * 2 * pi / heartCount) + random.nextDouble() * 0.5;
      final distance = 80 + random.nextDouble() * 40;

      final endX = tapPosition.dx + cos(angle) * distance;
      final endY =
          tapPosition.dy +
          sin(angle) * distance -
          100 -
          random.nextDouble() * 50;

      animations.add(
        LikeAnimation(
          startPosition: tapPosition,
          endPosition: Offset(endX, endY),
          duration: Duration(milliseconds: 1200 + random.nextInt(400)),
          delay: i * 0.1, // Staggered delay
        ),
      );
    }

    return animations;
  }
}
