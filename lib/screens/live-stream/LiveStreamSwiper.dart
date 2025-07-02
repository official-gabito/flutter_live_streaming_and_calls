import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'live_details_page.dart';

class LiveStreamSwiper extends StatefulWidget {
  final String initialLiveID;
  final String currentUserID;

  const LiveStreamSwiper({
    Key? key,
    required this.initialLiveID,
    required this.currentUserID,
  }) : super(key: key);

  @override
  State<LiveStreamSwiper> createState() => _LiveStreamSwiperState();
}

class _LiveStreamSwiperState extends State<LiveStreamSwiper> {
  List<Map<String, dynamic>> liveStreams = [];
  int currentIndex = 0;
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _fetchLiveStreams();
  }

  Future<void> _fetchLiveStreams() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('live_streams')
              .where('status', isEqualTo: 'live')
              .orderBy('startedAt', descending: true)
              .get();

      final List<Map<String, dynamic>> validStreams = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final lastUpdated = data['lastUpdated'] as Timestamp?;

        // Only include streams that have been updated in the last minute
        if (lastUpdated != null) {
          final timeSinceUpdate = DateTime.now().difference(
            lastUpdated.toDate(),
          );
          if (timeSinceUpdate.inMinutes < 1) {
            validStreams.add(data);
          }
        }
      }

      if (mounted) {
        setState(() {
          liveStreams = validStreams;
          currentIndex = liveStreams.indexWhere(
            (stream) => stream['liveID'] == widget.initialLiveID,
          );
          if (currentIndex == -1) currentIndex = 0;
          currentIndexNotifier.value = currentIndex;
        });
      }
    } catch (e) {
      debugPrint('Error fetching live streams: $e');
    }
  }

  @override
  void dispose() {
    currentIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (liveStreams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: liveStreams.length,
      onPageChanged: (index) {
        setState(() {
          currentIndex = index;
          currentIndexNotifier.value = index;
        });
      },
      itemBuilder: (context, index) {
        return LiveDetailsPageWrapper(
          key: ValueKey(liveStreams[index]['liveID']), // Add unique key
          liveStreamData: liveStreams[index],
          index: index,
          currentIndexNotifier: currentIndexNotifier,
          currentUserID: widget.currentUserID,
        );
      },
    );
  }
}

class LiveDetailsPageWrapper extends StatelessWidget {
  final Map<String, dynamic> liveStreamData;
  final int index;
  final ValueNotifier<int> currentIndexNotifier;
  final String currentUserID;

  const LiveDetailsPageWrapper({
    super.key,
    required this.liveStreamData,
    required this.index,
    required this.currentIndexNotifier,
    required this.currentUserID,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: currentIndexNotifier,
      builder: (context, currentIndex, child) {
        if (currentIndex == index) {
          return LiveDetailsPage(
            liveID: liveStreamData['liveID'],
            hostUserID: liveStreamData['userID'],
            currentUserID: currentUserID,
            isHost: false,
            streamTitle: liveStreamData['streamTitle'],
            isInSwiper: true,
          );
        } else {
          return Container(color: Colors.black);
        }
      },
    );
  }
}
