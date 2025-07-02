// Gabito/Template developer: Gabriel Naandum
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_live_streaming_and_calls/screens/live-stream/LiveStreamSwiper.dart';
import 'package:flutter_live_streaming_and_calls/screens/live-stream/go_live_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class LiveStreamListPage extends StatefulWidget {
  final String currentUserID;
  final bool isTabView;

  const LiveStreamListPage({
    super.key,
    required this.currentUserID,
    this.isTabView = false,
  });

  @override
  State<LiveStreamListPage> createState() => _LiveStreamListPageState();
}

class _LiveStreamListPageState extends State<LiveStreamListPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  String _searchQuery = '';
  bool _isLoading = true;
  GeoPoint? _userLocation;
  final Color _themeColor = const Color(0xFFA84BC2);
  Map<String, dynamic> _userData = {};

  // Tabs for different stream categories ("Liked" tab removed)
  final List<String> _tabs = ["All", "Popular", "Nearby"];

  // Custom tab style for a modern look
  List<Widget> _buildStyledTabs() {
    return _tabs.asMap().entries.map((entry) {
      final int idx = entry.key;
      final String tab = entry.value;
      final bool isSelected = _tabController.index == idx;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white24,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          tab,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _fetchUserData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Fetch current user data including location
  Future<void> _fetchUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.currentUserID)
              .get();

      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data() as Map<String, dynamic>;
          if (_userData.containsKey('location') &&
              _userData['location'] is GeoPoint) {
            _userLocation = _userData['location'] as GeoPoint;
          }
        });

        debugPrint(
          'User location: ${_userLocation?.latitude}, ${_userLocation?.longitude}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Request necessary permissions for live streaming
  Future<bool> _requestPermissions() async {
    try {
      final statuses =
          await [Permission.camera, Permission.microphone].request();

      return statuses[Permission.camera]!.isGranted &&
          statuses[Permission.microphone]!.isGranted;
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  // Navigate to streamer's live room as audience
  void _joinLiveStream(String liveID, String hostUserID) async {
    final user = FirebaseAuth.instance.currentUser;
    final currentUserID = user?.uid ?? widget.currentUserID;

    if (currentUserID.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User ID is missing. Please log in again.'),
        ),
      );
      return;
    }

    try {
      final streamDoc =
          await FirebaseFirestore.instance
              .collection('live_streams')
              .doc(liveID)
              .get();

      if (!streamDoc.exists || streamDoc.data()?['status'] != 'live') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This live stream has ended')),
          );
        }
        return;
      }

      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (context) => LiveStreamSwiper(
                  initialLiveID: liveID,
                  currentUserID: currentUserID,
                ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error joining live stream: $e');
    }
  }

  // Navigate to the Go Live page
  void _navigateToGoLive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final hasPermissions = await _requestPermissions();

      if (!hasPermissions) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera and microphone permissions are required to go live',
            ),
            backgroundColor: Color(0xFFA84BC2),
          ),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) => GoLivePage(
                currentUserID: user.uid,
                username:
                    user.displayName ?? "User_${user.uid.substring(0, 6)}",
              ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to be logged in to go live'),
          backgroundColor: Color(0xFFA84BC2),
        ),
      );
    }
  }

  // Calculate distance between current user and streamer
  double _calculateDistance(GeoPoint? streamLocation) {
    if (_userLocation == null || streamLocation == null) {
      return 999999;
    }

    try {
      return Geolocator.distanceBetween(
            _userLocation!.latitude,
            _userLocation!.longitude,
            streamLocation.latitude,
            streamLocation.longitude,
          ) /
          1000;
    } catch (e) {
      debugPrint('Error calculating distance: $e');
      return 999999;
    }
  }

  // Generate query for streams based on selected tab ("Liked" logic removed)
  Query<Map<String, dynamic>> _getStreamQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('live_streams')
        .where('status', isEqualTo: 'live');

    switch (_tabs[_tabController.index]) {
      case "Popular":
        return query.orderBy('viewerCount', descending: true);
      case "Nearby":
        return query;
      case "All":
      default:
        return query;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          widget.isTabView
              ? null
              : AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                titleTextStyle: const TextStyle(color: Colors.white),
                title: const Text(
                  'Live Streams',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: _navigateToGoLive,
                    child: const Text(
                      'Go Live',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      CupertinoIcons.dot_radiowaves_left_right,
                      color: Colors.blue,
                    ),
                    onPressed: _navigateToGoLive,
                    tooltip: 'Go Live',
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Container(
                    color: Colors.black,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicator: const BoxDecoration(), // Remove default indicator
                      tabs: _buildStyledTabs(),
                      onTap: (_) => setState(() {}),
                    ),
                  ),
                ),
              ),
      body: Column(
        children: [
          if (widget.isTabView)
            Container(
              color: Colors.black,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicator: const BoxDecoration(),
                tabs: _buildStyledTabs(),
                onTap: (_) => setState(() {}),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search streams...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search, color: Colors.blue),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _getStreamQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFA84BC2),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.black),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tv_off, size: 70, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        Text(
                          "No active streams right now",
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _navigateToGoLive,
                          icon: const Icon(
                            CupertinoIcons.dot_radiowaves_left_right,
                          ),
                          label: const Text("Start streaming"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _themeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                var streamDocs = snapshot.data!.docs;

                if (_tabs[_tabController.index] == "Nearby" &&
                    _userLocation != null) {
                  var streamsWithDistance =
                      streamDocs.map((doc) {
                        final data = doc.data();
                        GeoPoint? hostLocation;
                        if (data.containsKey('hostLocation') &&
                            data['hostLocation'] is GeoPoint) {
                          hostLocation = data['hostLocation'] as GeoPoint;
                        }
                        return {
                          'doc': doc,
                          'distance': _calculateDistance(hostLocation),
                        };
                      }).toList();

                  streamsWithDistance.sort(
                    (a, b) => (a['distance'] as double).compareTo(
                      b['distance'] as double,
                    ),
                  );

                  streamDocs =
                      streamsWithDistance
                          .map(
                            (item) =>
                                item['doc']
                                    as QueryDocumentSnapshot<
                                      Map<String, dynamic>
                                    >,
                          )
                          .toList();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  color: _themeColor,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.7,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: streamDocs.length,
                      itemBuilder: (context, index) {
                        final streamData = streamDocs[index].data();
                        final String liveID = streamData['liveID'] ?? '';
                        final String userID = streamData['userID'] ?? '';
                        final String streamTitle =
                            streamData['streamTitle'] ?? 'Live Stream';
                        final int viewerCount = streamData['viewerCount'] ?? 0;

                        return FutureBuilder<DocumentSnapshot>(
                          future:
                              FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(userID)
                                  .get(),
                          builder: (context, userSnapshot) {
                            if (userSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const LiveStreamSkeletonTile();
                            }

                            if (!userSnapshot.hasData ||
                                userSnapshot.data == null) {
                              return const SizedBox();
                            }

                            final userData =
                                userSnapshot.data!.data()
                                    as Map<String, dynamic>?;

                            if (userData == null) {
                              return const SizedBox();
                            }

                            String firstName = userData['firstName'] ?? '';
                            String lastName = userData['lastName'] ?? '';
                            String displayName = '';

                            if (firstName.isNotEmpty || lastName.isNotEmpty) {
                              displayName = '$firstName $lastName'.trim();
                            } else {
                              displayName =
                                  userData['username'] ?? 'Unknown User';
                            }

                            final String city = userData['city'] ?? '';
                            final String country = userData['country'] ?? '';
                            final String location = [
                              city,
                              country,
                            ].where((element) => element.isNotEmpty).join(', ');

                            String? profilePhoto;
                            if (userData['photos'] != null &&
                                userData['photos'] is List &&
                                (userData['photos'] as List).isNotEmpty) {
                              profilePhoto = userData['photos'][0];
                            }

                            if (_searchQuery.isNotEmpty &&
                                !displayName.toLowerCase().contains(
                                  _searchQuery,
                                ) &&
                                !location.toLowerCase().contains(
                                  _searchQuery,
                                ) &&
                                !streamTitle.toLowerCase().contains(
                                  _searchQuery,
                                )) {
                              return const SizedBox();
                            }

                            double? distance;
                            if (_tabs[_tabController.index] == "Nearby" &&
                                userData['location'] is GeoPoint &&
                                _userLocation != null) {
                              distance = _calculateDistance(
                                userData['location'],
                              );
                            }

                            return LiveStreamTile(
                              profilePhoto: profilePhoto,
                              username: displayName,
                              liveID: liveID,
                              userID: userID,
                              streamTitle: streamTitle,
                              viewerCount: viewerCount,
                              location: location,
                              distance: distance,
                              onTap: () => _joinLiveStream(liveID, userID),
                            );
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class LiveStreamTile extends StatelessWidget {
  final String? profilePhoto;
  final String username;
  final String liveID;
  final String userID;
  final String streamTitle;
  final int viewerCount;
  final String location;
  final double? distance;
  final VoidCallback onTap;

  const LiveStreamTile({
    Key? key,
    required this.profilePhoto,
    required this.username,
    required this.liveID,
    required this.userID,
    required this.streamTitle,
    required this.viewerCount,
    this.location = '',
    this.distance,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child:
                        profilePhoto != null && profilePhoto!.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl: profilePhoto!,
                              fit: BoxFit.cover,
                              placeholder:
                                  (context, url) => Container(
                                    color: const Color(
                                      0xFF8E24AA,
                                    ).withOpacity(0.2),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Color(0xFF8E24AA),
                                            ),
                                      ),
                                    ),
                                  ),
                              errorWidget:
                                  (context, url, error) => Container(
                                    color: const Color(
                                      0xFF8E24AA,
                                    ).withOpacity(0.2),
                                    child: const Center(
                                      child: Icon(
                                        Icons.image_not_supported,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                            )
                            : Container(
                              color: const Color(0xFF8E24AA).withOpacity(0.2),
                              child: const Center(
                                child: Icon(
                                  Icons.person,
                                  size: 48,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                          stops: const [0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: Colors.white, size: 8),
                          SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          streamTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.remove_red_eye,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$viewerCount viewers',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            if (distance != null) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.place,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${distance!.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.grey[200],
                    backgroundImage:
                        profilePhoto != null && profilePhoto!.isNotEmpty
                            ? CachedNetworkImageProvider(profilePhoto!)
                            : const AssetImage('assets/default_avatar.png')
                                as ImageProvider,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (location.isNotEmpty)
                          Text(
                            location,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveStreamSkeletonTile extends StatelessWidget {
  const LiveStreamSkeletonTile({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 50,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
