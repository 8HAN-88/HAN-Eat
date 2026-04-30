import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/user_service.dart';
import 'public_profile_page.dart';

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({Key? key}) : super(key: key);

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final _ctrl = TextEditingController();
  Stream<QuerySnapshot>? _stream;

  void _onSearchChanged() {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _stream = null);
      return;
    }
    final end = '$q\uf8ff';
    setState(() {
      _stream = FirebaseFirestore.instance
          .collection('user_profiles')
          .orderBy('displayName_lower')
          .startAt([q])
          .endAt([end])
          .limit(50)
          .snapshots();
    });
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onSearchChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search users'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Search by name'),
            ),
          ),
          Expanded(
            child: _stream == null
                ? const Center(child: Text('Type to search'))
                : StreamBuilder<QuerySnapshot>(
                    stream: _stream,
                    builder: (context, snap) {
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final docs = snap.data!.docs;
                      if (docs.isEmpty)
                        return const Center(child: Text('No users found'));
                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (c, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final uid = docs[i].id;
                          final name = d['displayName'] ?? 'No name';
                          final avatar = d['avatarUrl'] as String?;
                          return ListTile(
                            leading: avatar != null
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(avatar))
                                : const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(name),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PublicProfilePage(uid: uid))),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
