import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../data/collection.dart';
import '../data/scryfall.dart';
import '../scan_controller.dart';
import 'collection_screen.dart';
import 'guide_overlay.dart';

class ScannerScreen extends StatefulWidget {
  final CollectionStore collection;
  final ScryfallClient scryfall;
  const ScannerScreen({super.key, required this.collection, required this.scryfall});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  ScanController? _scan;
  String? _error;
  bool _foil = false;
  bool _autoAdd = false;
  ScanHit? _autoAddedHit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final s = ScanController(widget.scryfall);
    s.addListener(_onScanChanged);
    s.setAutoAdd(_autoAdd);
    setState(() {
      _scan = s;
      _error = null;
    });
    try {
      await s.init();
    } on CameraException catch (e) {
      if (!mounted || _scan != s) return;
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Camera permission is needed to scan cards.'
          : 'Camera error: ${e.description ?? e.code}');
    } catch (e) {
      if (!mounted || _scan != s) return; // disposed mid-start (app backgrounded)
      setState(() => _error = 'Camera error: $e');
    }
  }

  void _stop() {
    final s = _scan;
    _scan = null;
    s?.removeListener(_onScanChanged);
    s?.dispose();
  }

  void _onScanChanged() {
    final s = _scan;
    if (s == null) return;
    if (s.autoAdd && s.hit != null && !identical(s.hit, _autoAddedHit)) {
      _autoAddedHit = s.hit;
      final card = s.hit!.card;
      widget.collection.add(card, foil: _foil);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added ${card.name}'),
        duration: const Duration(milliseconds: 1200),
      ));
      Future.delayed(const Duration(milliseconds: 600), () => _scan?.resume(suppressCurrent: true));
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Not 'inactive': the camera permission dialog triggers that.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_scan != null) setState(_stop);
    } else if (state == AppLifecycleState.resumed && _scan == null) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _scan;
    final cam = s?.camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Dark Scanner'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: Icon(s?.torchOn == true ? Icons.flashlight_on : Icons.flashlight_off),
            onPressed: s == null ? null : s.toggleTorch,
          ),
          ListenableBuilder(
            listenable: widget.collection,
            builder: (context, _) => TextButton.icon(
              icon: const Icon(Icons.collections_bookmark),
              label: Text('${widget.collection.totalCards}'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CollectionScreen(collection: widget.collection),
              )),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: cam == null || !cam.value.isInitialized
                        ? const CircularProgressIndicator()
                        : CameraPreview(
                            cam,
                            child: CustomPaint(
                              painter: GuideOverlay(quad: s!.quadNorm, sidesFound: s.sidesFound),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (s.hit == null && s.paused) s.resume();
                                },
                              ),
                            ),
                          ),
                  ),
                ),
                if (s != null) _statusBar(s),
                if (s?.hit != null && !_autoAdd) _resultPanel(s!) else _controls(s),
              ],
            ),
    );
  }

  Widget _statusBar(ScanController s) {
    final (IconData icon, String text, Color color) = switch (s.hint) {
      ScanHint.glare => (Icons.wb_sunny, 'Glare on the title — tilt the card a little or turn the torch off', Colors.amber),
      ScanHint.tooDark => (Icons.dark_mode, 'Too dark — try the torch', Colors.amber),
      ScanHint.noEdges => (Icons.crop_free, 'Fill the frame with the card', Colors.white70),
      ScanHint.lookingUp => (Icons.search, s.status, Colors.lightBlueAccent),
      ScanHint.offline => (Icons.cloud_off, 'Offline name list unavailable — using online search. ${s.status}', Colors.orangeAccent),
      ScanHint.none => (Icons.document_scanner, s.status, Colors.white70),
    };
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color), maxLines: 2)),
        Text(
          s.sidesFound >= 3 ? 'edges ✓' : 'edges ${s.sidesFound}/4',
          style: TextStyle(color: s.sidesFound >= 3 ? Colors.greenAccent : Colors.white38, fontSize: 12),
        ),
      ]),
    );
  }

  Widget _controls(ScanController? s) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          FilterChip(
            label: const Text('Foil'),
            selected: _foil,
            onSelected: (v) => setState(() => _foil = v),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Auto-add'),
            selected: _autoAdd,
            onSelected: (v) {
              setState(() => _autoAdd = v);
              s?.setAutoAdd(v);
            },
          ),
          const Spacer(),
          if (s?.lastRawName != null)
            Flexible(
              child: Text('OCR: ${s!.lastRawName}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
        ]),
      ),
    );
  }

  Widget _resultPanel(ScanController s) {
    final hit = s.hit!;
    final c = hit.card;
    final price = _foil ? (c.priceEurFoil ?? c.priceUsdFoil) : (c.priceEur ?? c.priceUsd);
    final currency = _foil
        ? (c.priceEurFoil != null ? '€' : r'$')
        : (c.priceEur != null ? '€' : r'$');
    return SafeArea(
      top: false,
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (c.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(c.imageUrl!, width: 80, fit: BoxFit.cover),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${c.setName} (${c.setCode.toUpperCase()}) #${c.collectorNumber}',
                    style: Theme.of(context).textTheme.bodySmall),
                Row(children: [
                  Icon(hit.exactPrinting ? Icons.verified : Icons.help_outline,
                      size: 14, color: hit.exactPrinting ? Colors.greenAccent : Colors.amber),
                  const SizedBox(width: 4),
                  Text(hit.exactPrinting ? 'Exact printing' : 'Printing guessed',
                      style: Theme.of(context).textTheme.labelSmall),
                  const Spacer(),
                  if (price != null) Text('$currency$price'),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                    onPressed: () {
                      widget.collection.add(c, foil: _foil);
                      s.resume(suppressCurrent: true);
                    },
                  ),
                  FilterChip(
                    label: const Text('Foil'),
                    selected: _foil,
                    onSelected: (v) => setState(() => _foil = v),
                  ),
                  OutlinedButton(
                    onPressed: () => _pickPrinting(s, c),
                    child: const Text('Printing'),
                  ),
                  TextButton(onPressed: () => s.resume(), child: const Text('Skip')),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickPrinting(ScanController s, CardPrint current) async {
    final picked = await showModalBottomSheet<CardPrint>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => FutureBuilder<List<CardPrint>>(
          future: widget.scryfall.printings(current.name),
          builder: (ctx, snap) {
            if (snap.hasError) return Center(child: Text('Could not load printings: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            return ListView.builder(
              controller: scroll,
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final p = list[i];
                return ListTile(
                  selected: p.id == current.id,
                  leading: p.imageUrl == null ? null : Image.network(p.imageUrl!, width: 36),
                  title: Text('${p.setName} (${p.setCode.toUpperCase()})'),
                  subtitle: Text('#${p.collectorNumber} · ${p.rarity}'),
                  trailing: Text(p.priceEur != null ? '€${p.priceEur}' : (p.priceUsd != null ? '\$${p.priceUsd}' : '')),
                  onTap: () => Navigator.of(ctx).pop(p),
                );
              },
            );
          },
        ),
      ),
    );
    if (picked != null) s.choosePrinting(picked);
  }
}
