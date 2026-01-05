import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/translation_service.dart';
import '../../models/collection.dart';
import 'import_curated_list_screen.dart' as import_curated;

class CollectionListScreen extends StatefulWidget {
  const CollectionListScreen({super.key});

  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> {
  late Future<List<Collection>> _collectionsFuture;

  @override
  void initState() {
    super.initState();
    _refreshCollections();
  }

  void _refreshCollections() {
    setState(() {
      _collectionsFuture = Provider.of<ApiService>(
        context,
        listen: false,
      ).getCollections();
    });
  }

  Future<void> _createCollection() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            TranslationService.translate(context, 'create_collection'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(context, 'name'),
                ),
              ),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'description',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(TranslationService.translate(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    final apiService = Provider.of<ApiService>(
                      context,
                      listen: false,
                    );
                    await apiService.createCollection(
                      nameController.text,
                      description: descriptionController.text.isEmpty
                          ? null
                          : descriptionController.text,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      _refreshCollections();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                }
              },
              child: Text(TranslationService.translate(context, 'create')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'collections')),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_motion),
            tooltip: 'Discover Curated Collections',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const import_curated.ImportCuratedListScreen(),
                ),
              );
              if (result == true) {
                _refreshCollections();
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Collection>>(
        future: _collectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.collections_bookmark,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    TranslationService.translate(context, 'no_collections'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const import_curated.ImportCuratedListScreen(),
                        ),
                      );
                      if (result == true) {
                        _refreshCollections();
                      }
                    },
                    icon: const Icon(Icons.auto_awesome_motion),
                    label: const Text('Discover Curated Lists'),
                  ),
                ],
              ),
            );
          }

          final collections = snapshot.data!;
          return ListView.builder(
            itemCount: collections.length,
            itemBuilder: (context, index) {
              final collection = collections[index];
              return ListTile(
                leading: const Icon(Icons.folder),
                title: Text(collection.name),
                subtitle: Text('${collection.totalBooks} books'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          TranslationService.translate(
                            context,
                            'confirm_delete',
                          ),
                        ),
                        content: Text(
                          TranslationService.translate(
                            context,
                            'delete_collection_confirm',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && context.mounted) {
                      try {
                        await Provider.of<ApiService>(
                          context,
                          listen: false,
                        ).deleteCollection(collection.id);
                        _refreshCollections();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    }
                  },
                ),
                onTap: () {
                  context.push(
                    '/collections/${collection.id}',
                    extra: collection,
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCollection,
        child: const Icon(Icons.add),
      ),
    );
  }
}
