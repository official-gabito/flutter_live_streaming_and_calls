// Gabito/Template developer: Gabriel Naandum
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_live_streaming_and_calls/screens/live-stream/live_details_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:uuid/uuid.dart';

class GoLivePage extends StatefulWidget {
  final String currentUserID;
  final String username;

  const GoLivePage({
    super.key,
    required this.currentUserID,
    required this.username,
  });

  @override
  State<GoLivePage> createState() => _GoLivePageState();
}

class _GoLivePageState extends State<GoLivePage> {
  final TextEditingController _titleController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _profilePhoto;
  String _displayName = '';
  DateTime? _lastButtonPress; // Track last button press time
  static const int _debounceDuration = 2000; // 2 seconds debounce

  // Theme color
  final themeColor = const Color(0xFFA84BC2);

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _checkPermissions();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // Enhanced user profile fetching
  Future<void> _fetchUserProfile() async {
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.currentUserID)
              .get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null) {
          // Get profile photo from photos array
          if (userData['photos'] != null &&
              userData['photos'] is List &&
              (userData['photos'] as List).isNotEmpty) {
            setState(() {
              _profilePhoto = userData['photos'][0];
            });
            debugPrint('Fetched profile photo: $_profilePhoto');
          }

          // Get display name - prioritize firstName + lastName
          String firstName = userData['firstName'] ?? '';
          String lastName = userData['lastName'] ?? '';

          if (firstName.isNotEmpty || lastName.isNotEmpty) {
            setState(() {
              _displayName = '$firstName $lastName'.trim();
            });
          } else if (userData['username'] != null &&
              userData['username'].toString().isNotEmpty) {
            // Fall back to username if available
            setState(() {
              _displayName = userData['username'];
            });
          } else {
            // Last resort: use the username passed from constructor
            setState(() {
              _displayName = widget.username;
            });
          }

          debugPrint('Fetched display name: $_displayName');
        }
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      // Fallback to constructor username if error occurs
      setState(() {
        _displayName = widget.username;
      });
    }
  }

  // Check and request permissions
  Future<void> _checkPermissions() async {
    try {
      if (!kIsWeb) {
        if (Platform.isAndroid || Platform.isIOS) {
          Map<Permission, PermissionStatus> statuses =
              await [Permission.camera, Permission.microphone].request();

          if (statuses[Permission.camera]!.isDenied ||
              statuses[Permission.microphone]!.isDenied) {
            _showPermissionDialog();
          }
        }
      }
    } catch (e) {
      debugPrint('Permission check error: $e');
    }
  }

  // Show permission dialog
  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'Permissions Required',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Camera and microphone access is required to go live. Please grant these permissions in your device settings.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: Text(
                  'Open Settings',
                  style: TextStyle(color: themeColor),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  // Initialize stream
  Future<void> _initializeStream() async {
    if (!mounted) return;

    try {
      await _checkPermissions();
      final hasValidState = await _validateStreamState();
      if (!hasValidState) return;

      // Generate unique live ID
      final liveID = const Uuid().v4();

      // Create live stream document with proper initialization states
      await FirebaseFirestore.instance
          .collection('live_streams')
          .doc(liveID)
          .set({
            'liveID': liveID,
            'userID': widget.currentUserID,
            'hostName':
                _displayName.isNotEmpty ? _displayName : widget.username,
            'hostProfileUrl': _profilePhoto ?? '',
            'streamTitle': _titleController.text.trim(),
            'startedAt': FieldValue.serverTimestamp(),
            'status': 'active',
            'likeCount': 0,
            'viewerCount': 0,
            'lastUpdated': FieldValue.serverTimestamp(),
            'isStreamStarted': false, // Add this line
          });

      // Navigate to LiveDetailsPage as host
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => LiveDetailsPage(
                  liveID: liveID,
                  hostUserID: widget.currentUserID,
                  currentUserID: widget.currentUserID,
                  isHost: true,
                  streamTitle: _titleController.text.trim(),
                ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error initializing stream: $e');
      rethrow; // Rethrow to handle in _startLiveStream
    }
  }

  // Validate stream state
  Future<bool> _validateStreamState() async {
    try {
      final activeStreams =
          await FirebaseFirestore.instance
              .collection('live_streams')
              .where('userID', isEqualTo: widget.currentUserID)
              .where('status', whereIn: ['active', 'initializing'])
              .get();

      if (activeStreams.docs.isNotEmpty) {
        final streamDoc = activeStreams.docs.first;
        final data = streamDoc.data();
        final lastUpdated = data['lastUpdated'] as Timestamp?;
        if (lastUpdated != null) {
          final now = Timestamp.now();
          if (now.seconds - lastUpdated.seconds > 60) {
            // Stream is stale, end it automatically
            await streamDoc.reference.update({
              'status': 'ended',
              'endedAt': FieldValue.serverTimestamp(),
            });
            debugPrint('Automatically ended stale stream: ${streamDoc.id}');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'You already have an active stream. Please end it before starting a new one.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            return false;
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error validating stream state: $e');
      return false;
    }
  }

  // Updated start live stream method with debouncing
  void _startLiveStream() async {
    // Check if button was pressed within debounce duration
    if (_lastButtonPress != null &&
        DateTime.now().difference(_lastButtonPress!).inMilliseconds <
            _debounceDuration) {
      debugPrint('Button press ignored due to debounce');
      return;
    }

    // Validate form
    if (!_formKey.currentState!.validate()) return;

    // Update last button press time
    _lastButtonPress = DateTime.now();

    // Disable button and show loading state
    setState(() => _isLoading = true);

    try {
      await _initializeStream();
    } catch (e) {
      debugPrint('Error starting live stream: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start live stream: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Re-enable button only if still mounted
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Go Live',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile preview with updated user info
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[800],
                        backgroundImage:
                            _profilePhoto != null && _profilePhoto!.isNotEmpty
                                ? NetworkImage(_profilePhoto!)
                                : null,
                        child:
                            _profilePhoto == null || _profilePhoto!.isEmpty
                                ? const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                )
                                : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _displayName.isNotEmpty ? _displayName : "User",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: themeColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'HOST',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Stream title
                const Text(
                  'Stream Title',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter stream title...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: themeColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a stream title';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 40),

                // Tips
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: themeColor.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tips for a Great Stream:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTip(
                        'Make sure you have a stable internet connection',
                      ),
                      _buildTip('Find a quiet environment with good lighting'),
                      _buildTip('Interact with your viewers regularly'),
                      _buildTip('Be mindful of community guidelines'),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Go Live Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _startLiveStream,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 5,
                    ),
                    child:
                        _isLoading
                            ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.live_tv, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'START LIVE STREAM',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: themeColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

// Live host page that redirects to LiveDetailsPage with host configuration
class LiveHostPage extends StatelessWidget {
  final String liveID;
  final String currentUserID;
  final String username;
  final String streamTitle;

  const LiveHostPage({
    Key? key,
    required this.liveID,
    required this.currentUserID,
    required this.username,
    required this.streamTitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Redirect to LiveDetailsPage with isHost flag set to true
    return LiveDetailsPage(
      liveID: liveID,
      hostUserID: currentUserID, // For host, currentUserID is the hostUserID
      currentUserID: currentUserID,
      isHost: true, // This flag will enable host controls
      streamTitle: streamTitle,
    );
  }
}
