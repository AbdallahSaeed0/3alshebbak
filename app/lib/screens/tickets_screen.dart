import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_data.dart';
import '../data/models.dart';
import '../data/tickets.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

void openTickets(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const TicketsScreen()));

/// My tickets: screenshots of bookings, kept on the phone so they're one tap
/// away at the cinema door.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  bool _adding = false;

  Future<void> _add(TicketStore store) async {
    final data = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _adding = true);
    try {
      // Shrunk so a phone screenshot stays a few hundred KB.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final movie = await _askFilm(context, data);
      if (movie == null) return; // Dismissed: nothing added.
      await store.add(bytes, movieId: movie.id.isEmpty ? null : movie.id);
      messenger.showSnackBar(
        SnackBar(content: Text('اتحفظت', style: AppText.body(13))),
      );
    } catch (e) {
      debugPrint('Adding a ticket failed: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'معرفناش نحفظ الصورة. لو على الويب، المساحة ممكن تكون خلصت.',
            style: AppText.body(13),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تذاكري', style: AppText.display(24)),
        backgroundColor: AppColors.background,
      ),
      body: FutureBuilder<TicketStore>(
        future: TicketStore.load(),
        builder: (context, snap) {
          final store = snap.data;
          if (store == null) {
            return snap.hasError
                ? Center(
                    child: Text(
                      'معرفناش نفتح تذاكرك',
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  )
                : const Center(child: CircularProgressIndicator());
          }
          return ListenableBuilder(
            listenable: store,
            builder: (context, _) => Stack(
              children: [
                _TicketGrid(store: store),
                PositionedDirectional(
                  start: 20,
                  end: 20,
                  bottom: 20,
                  child: SafeArea(
                    top: false,
                    child: FilledButton.icon(
                      onPressed: _adding ? null : () => _add(store),
                      icon: _adding
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onGold,
                              ),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('ضيف اسكرين تذكرة'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.onGold,
                        minimumSize: const Size.fromHeight(52),
                        textStyle: AppText.body(16, weight: FontWeight.w700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Which film a new ticket is for. An empty-id movie means "none"; null
/// means the sheet was dismissed.
Future<Movie?> _askFilm(BuildContext context, AppData data) {
  final films = [for (final s in data.nowShowing()) s.movie];
  const none = Movie(id: '', title: '');
  return showModalBottomSheet<Movie>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('التذكرة دي لفيلم إيه؟', style: AppText.display(22)),
          ),
          ListTile(
            leading: const Icon(Icons.confirmation_number_outlined),
            title: Text(
              'من غير فيلم',
              style: AppText.body(15, weight: FontWeight.w600),
            ),
            onTap: () => Navigator.of(context).pop(none),
          ),
          const Divider(color: AppColors.hairline, indent: 20, endIndent: 20),
          for (final m in films)
            ListTile(
              leading: Poster(movie: m, width: 32, height: 48, radius: 4),
              title: Text(
                m.displayTitle,
                style: AppText.body(15, weight: FontWeight.w600),
              ),
              onTap: () => Navigator.of(context).pop(m),
            ),
        ],
      ),
    ),
  );
}

class _TicketGrid extends StatelessWidget {
  const _TicketGrid({required this.store});
  final TicketStore store;

  @override
  Widget build(BuildContext context) {
    final tickets = store.all;
    if (tickets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 100),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.confirmation_number_outlined,
                size: 56,
                color: AppColors.gold,
              ),
              const SizedBox(height: 16),
              Text(
                'مفيش تذاكر لسه',
                style: AppText.display(22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'حجزت؟ خد اسكرين للتذكرة وحطها هنا، تلاقيها بسرعة على باب السينما. بتتحفظ على موبايلك بس.',
                style: AppText.body(14, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final data = AppScope.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.56,
      ),
      itemCount: tickets.length,
      itemBuilder: (context, i) {
        final t = tickets[i];
        final movie = data.catalog.movies[t.movieId];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _TicketView(store: store, ticket: t),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
                  tag: 'ticket-${t.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.hairline),
                      image: DecorationImage(
                        image: store.image(t),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                movie?.displayTitle ?? 'تذكرة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(13, weight: FontWeight.w700),
              ),
              Text(
                'اتضافت ${dayLabel(isoDate(t.addedAt))}',
                style: AppText.body(11, color: AppColors.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One ticket, full screen and zoomable, to show at the door.
class _TicketView extends StatelessWidget {
  const _TicketView({required this.store, required this.ticket});

  final TicketStore store;
  final Ticket ticket;

  Future<void> _delete(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'تمسح التذكرة دي؟',
          style: AppText.body(17, weight: FontWeight.w700),
        ),
        content: Text(
          'هتتمسح من التطبيق بس، مش من صور الموبايل.',
          style: AppText.body(14, color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لأ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('امسح', style: TextStyle(color: AppColors.amber)),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await store.remove(ticket);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final movie = AppScope.of(context).catalog.movies[ticket.movieId];
    final path = store.path(ticket);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          movie?.displayTitle ?? 'تذكرة',
          style: AppText.body(17, weight: FontWeight.w700),
        ),
        actions: [
          if (path != null)
            IconButton(
              tooltip: 'شارك',
              icon: const Icon(Icons.ios_share),
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(files: [XFile(path)])),
            ),
          IconButton(
            tooltip: 'امسح',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Hero(
            tag: 'ticket-${ticket.id}',
            child: Image(image: store.image(ticket)),
          ),
        ),
      ),
    );
  }
}
